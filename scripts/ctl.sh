#!/bin/bash
# Roblox Limit - 設定操作 CLI（GUI からもこれを呼ぶ）
# 参照系 (status) は誰でも実行可。変更系は root（= sudo / 管理者認証）が必要。
set -u

APP_DIR="${ROBLOX_LIMIT_DIR:-/Library/Application Support/RobloxLimit}"
CONFIG="$APP_DIR/config"
STATE="$APP_DIR/state"

usage() {
  cat <<'USAGE'
使い方: roblox-limit <コマンド>

  status            今日の使用状況と設定を表示
  status --raw      機械可読形式で表示（GUI 用）
  enable            制限を ON
  disable           制限を OFF
  set-weekday <分>  平日の上限（分）を設定
  set-weekend <分>  休日（土日）の上限（分）を設定
  set-curfew <開始 HH:MM> <終了 HH:MM>  利用可能な時間帯を設定
  add-bonus <分>    今日だけ上限を延長（翌日自動リセット）
  reset-today       今日の使用時間カウントをゼロに戻す
  set-user <名前>   監視対象のアカウント名を設定

変更系コマンドは sudo が必要です。例: sudo roblox-limit set-weekday 120
USAGE
}

get() { # $1=key $2=file
  grep "^$1=" "$2" 2>/dev/null | head -1 | cut -d= -f2-
}

set_key() { # $1=file $2=key $3=value
  local f="$1" k="$2" v="$3"
  touch "$f"
  if grep -q "^$k=" "$f" 2>/dev/null; then
    sed -i '' "s|^$k=.*|$k=$v|" "$f"
  else
    echo "$k=$v" >> "$f"
  fi
}

need_write() {
  if [ "$(id -u)" != "0" ] && [ ! -w "$CONFIG" ]; then
    echo "エラー: このコマンドは管理者権限が必要です。sudo を付けて実行してください。" >&2
    exit 1
  fi
}

check_int() { # $1=値 $2=名前
  case "$1" in
    ''|*[!0-9]*) echo "エラー: $2 は数値（分）で指定してください: '$1'" >&2; exit 1 ;;
  esac
}

check_hhmm() {
  case "$1" in
    [0-2][0-9]:[0-5][0-9]) return 0 ;;
    *) echo "エラー: 時刻は HH:MM 形式で指定してください: '$1'" >&2; exit 1 ;;
  esac
}

# 今日の state を読む（日付が古ければゼロ扱い）
read_today_state() {
  today=$(date +%F)
  used=0; bonus=0
  if [ "$(get date "$STATE")" = "$today" ]; then
    used=$(get used "$STATE"); used=${used:-0}
    bonus=$(get bonus "$STATE"); bonus=${bonus:-0}
  fi
}

cmd="${1:-status}"
case "$cmd" in
  status)
    enabled=$(get enabled "$CONFIG");           enabled=${enabled:-0}
    weekday=$(get weekday_limit_min "$CONFIG"); weekday=${weekday:-120}
    weekend=$(get weekend_limit_min "$CONFIG"); weekend=${weekend:-180}
    a_start=$(get allowed_start "$CONFIG");     a_start=${a_start:-07:00}
    a_end=$(get allowed_end "$CONFIG");         a_end=${a_end:-21:00}
    t_user=$(get target_user "$CONFIG")
    read_today_state
    dow=$(date +%u)
    if [ "$dow" -ge 6 ]; then limit_min=$weekend; else limit_min=$weekday; fi
    limit_sec=$(( limit_min * 60 + bonus ))
    remain_sec=$(( limit_sec - used ))
    [ "$remain_sec" -lt 0 ] && remain_sec=0
    running=0
    if [ -n "$t_user" ]; then
      t_uid=$(id -u "$t_user" 2>/dev/null || echo "")
      if [ -n "$t_uid" ] && pgrep -U "$t_uid" -i "roblox" >/dev/null 2>&1; then running=1; fi
    fi
    if [ "${2:-}" = "--raw" ]; then
      printf 'enabled=%s\nweekday_limit_min=%s\nweekend_limit_min=%s\nallowed_start=%s\nallowed_end=%s\ntarget_user=%s\ndate=%s\nused_sec=%s\nbonus_sec=%s\nlimit_today_min=%s\nremain_sec=%s\nrunning=%s\n' \
        "$enabled" "$weekday" "$weekend" "$a_start" "$a_end" "$t_user" \
        "$today" "$used" "$bonus" "$(( limit_sec / 60 ))" "$remain_sec" "$running"
    else
      if [ "$enabled" = "1" ]; then state_txt="ON"; else state_txt="OFF"; fi
      if [ "$running" = "1" ]; then run_txt="起動中"; else run_txt="停止中"; fi
      echo "Roblox 制限        : $state_txt"
      echo "対象アカウント     : ${t_user:-（未設定）}"
      echo "Roblox             : $run_txt"
      echo "今日の使用         : $(( used / 60 ))分 / 上限 $(( limit_sec / 60 ))分（残り $(( remain_sec / 60 ))分）"
      echo "上限設定           : 平日 ${weekday}分 / 休日 ${weekend}分"
      echo "利用できる時間帯   : ${a_start}〜${a_end}"
      [ "$bonus" -gt 0 ] && echo "今日のボーナス     : +$(( bonus / 60 ))分"
    fi
    ;;
  enable)
    need_write; set_key "$CONFIG" enabled 1; echo "制限を ON にしました" ;;
  disable)
    need_write; set_key "$CONFIG" enabled 0; echo "制限を OFF にしました" ;;
  set-weekday)
    need_write; check_int "${2:-}" "平日上限"
    set_key "$CONFIG" weekday_limit_min "$2"; echo "平日上限を ${2}分 にしました" ;;
  set-weekend)
    need_write; check_int "${2:-}" "休日上限"
    set_key "$CONFIG" weekend_limit_min "$2"; echo "休日上限を ${2}分 にしました" ;;
  set-curfew)
    need_write; check_hhmm "${2:-}"; check_hhmm "${3:-}"
    set_key "$CONFIG" allowed_start "$2"
    set_key "$CONFIG" allowed_end "$3"
    echo "利用できる時間帯を ${2}〜${3} にしました" ;;
  add-bonus)
    need_write; check_int "${2:-}" "延長時間"
    read_today_state
    # state の日付が古い場合は今日の状態として作り直す（ボーナスが日付リセットで消えるのを防ぐ）
    printf 'date=%s\nused=%s\nbonus=%s\nwarned=0\n' \
      "$today" "$used" "$(( bonus + $2 * 60 ))" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
    chmod 644 "$STATE" 2>/dev/null
    echo "今日の上限を +${2}分 延長しました" ;;
  reset-today)
    need_write
    read_today_state
    printf 'date=%s\nused=0\nbonus=%s\nwarned=0\n' "$today" "$bonus" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
    chmod 644 "$STATE" 2>/dev/null
    echo "今日の使用時間をリセットしました" ;;
  set-user)
    need_write
    if ! id -u "${2:-}" >/dev/null 2>&1; then
      echo "エラー: ユーザー '${2:-}' が見つかりません" >&2; exit 1
    fi
    set_key "$CONFIG" target_user "$2"; echo "監視対象を '$2' にしました" ;;
  -h|--help|help)
    usage ;;
  *)
    usage; exit 1 ;;
esac
