#!/bin/bash
# Roblox Limit - 監視デーモン本体
# launchd (root) から30秒ごとに1回実行される。1回の実行で1 tick 分を処理して終了する。
#
# テスト用: 環境変数 ROBLOX_LIMIT_DIR でデータディレクトリを差し替えると
# root 不要で動作確認できる（通知は自分のセッションに直接出す）。
set -u

APP_DIR="${ROBLOX_LIMIT_DIR:-/Library/Application Support/RobloxLimit}"
CONFIG="$APP_DIR/config"
STATE="$APP_DIR/state"
USAGE_LOG="$APP_DIR/usage.log"
TICK="${ROBLOX_LIMIT_TICK:-30}"

[ -r "$CONFIG" ] || exit 0

# ---- config 読込 (key=value 形式) ----
enabled=1
weekday_limit_min=120
weekend_limit_min=180
allowed_start="07:00"
allowed_end="21:00"
target_user=""
proc_pattern="roblox"
while IFS='=' read -r k v; do
  case "$k" in
    enabled)            enabled="$v" ;;
    weekday_limit_min)  weekday_limit_min="$v" ;;
    weekend_limit_min)  weekend_limit_min="$v" ;;
    allowed_start)      allowed_start="$v" ;;
    allowed_end)        allowed_end="$v" ;;
    target_user)        target_user="$v" ;;
    proc_pattern)       proc_pattern="$v" ;;
  esac
done < "$CONFIG"

[ "$enabled" = "1" ] || exit 0
[ -n "$target_user" ] || exit 0
uid=$(id -u "$target_user" 2>/dev/null) || exit 0

# ---- state 読込 ----
today=$(date +%F)
s_date=""; used=0; bonus=0; warned=0
if [ -r "$STATE" ]; then
  while IFS='=' read -r k v; do
    case "$k" in
      date)   s_date="$v" ;;
      used)   used="$v" ;;
      bonus)  bonus="$v" ;;
      warned) warned="$v" ;;
    esac
  done < "$STATE"
fi

# 日付が変わったら前日の使用時間を履歴に残してリセット
if [ "$s_date" != "$today" ]; then
  if [ -n "$s_date" ]; then
    echo "$s_date used_min=$(( used / 60 ))" >> "$USAGE_LOG"
  fi
  used=0; bonus=0; warned=0
fi

save_state() {
  printf 'date=%s\nused=%s\nbonus=%s\nwarned=%s\n' \
    "$today" "$used" "$bonus" "$warned" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
  chmod 644 "$STATE" 2>/dev/null
}

# ---- Roblox プロセス検知 ----
# プロセス名のみで照合する（-f は使わない: ブラウザの URL 引数 "roblox.com" 等への誤爆防止）
pids=$(pgrep -U "$uid" -i "$proc_pattern" 2>/dev/null || true)
if [ -z "$pids" ]; then
  save_state
  exit 0
fi

used=$(( used + TICK ))

notify() { # $1=メッセージ
  local msg="$1"
  if [ "$(id -u)" = "$uid" ]; then
    /usr/bin/osascript -e "display notification \"$msg\" with title \"Roblox タイマー\" sound name \"Glass\"" >/dev/null 2>&1 || true
  else
    launchctl asuser "$uid" sudo -u "$target_user" \
      /usr/bin/osascript -e "display notification \"$msg\" with title \"Roblox タイマー\" sound name \"Glass\"" >/dev/null 2>&1 || true
  fi
}

kill_roblox() {
  pkill -9 -U "$uid" -i "$proc_pattern" 2>/dev/null || true
}

hm_to_min() { echo $(( 10#${1%%:*} * 60 + 10#${1##*:} )); }

# ---- 時間帯チェック（利用可能時間外なら即終了） ----
now_min=$(( 10#$(date +%H) * 60 + 10#$(date +%M) ))
start_min=$(hm_to_min "$allowed_start")
end_min=$(hm_to_min "$allowed_end")
if [ "$now_min" -lt "$start_min" ] || [ "$now_min" -ge "$end_min" ]; then
  notify "いまは Roblox を使えない時間です（つかえるのは ${allowed_start}〜${allowed_end}）"
  kill_roblox
  save_state
  exit 0
fi

# ---- 上限チェック（平日/休日別 + 当日ボーナス） ----
dow=$(date +%u)   # 1=月 ... 6=土 7=日
if [ "$dow" -ge 6 ]; then
  limit_sec=$(( weekend_limit_min * 60 + bonus ))
else
  limit_sec=$(( weekday_limit_min * 60 + bonus ))
fi

# 残り時間 = 「上限までの残り」と「利用終了時刻までの残り」の小さいほう
remain=$(( limit_sec - used ))
remain_curfew=$(( (end_min - now_min) * 60 ))
[ "$remain_curfew" -lt "$remain" ] && remain=$remain_curfew

if [ "$remain" -le 0 ]; then
  notify "今日の Roblox 時間はおしまい！また明日ね"
  kill_roblox
elif [ "$remain" -le 60 ]; then
  if [ "$warned" -lt 3 ]; then notify "残り1分！セーブしてね"; warned=3; fi
elif [ "$remain" -le 300 ]; then
  if [ "$warned" -lt 2 ]; then notify "Roblox はあと5分でおわりです"; warned=2; fi
elif [ "$remain" -le 600 ]; then
  if [ "$warned" -lt 1 ]; then notify "Roblox はあと10分でおわりです"; warned=1; fi
else
  warned=0   # ボーナス延長などで残りが増えた場合は警告段階を戻す
fi

save_state
exit 0
