#!/bin/bash
# PlayCap - settings CLI (also invoked by the GUI)
# Reading (status) works for everyone; changes require root (sudo / admin auth).
set -u

APP_DIR="${PLAYCAP_DIR:-/Library/Application Support/PlayCap}"
CONFIG="$APP_DIR/config"
STATE="$APP_DIR/state"

usage() {
  cat <<'USAGE'
Usage: playcap <command>

  status                 Show today's usage and current settings
  status --raw           Machine-readable output (used by the GUI)
  enable                 Turn limits ON
  disable                Turn limits OFF
  set-weekday <min>      Set weekday daily limit (minutes)
  set-weekend <min>      Set weekend daily limit (minutes)
  set-curfew <HH:MM> <HH:MM>   Set allowed time window (start end)
  set-targets <patterns> Comma-separated process name patterns (e.g. roblox,minecraft)
  set-lang <auto|ja|en>  Notification language
  add-bonus <min>        Extend today's limit (auto-resets tomorrow)
  reset-today            Reset today's usage counter
  set-user <name>        Set the monitored macOS account

Commands that change settings require sudo, e.g.: sudo playcap set-weekday 120
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
    echo "Error: this command requires administrator privileges. Run it with sudo." >&2
    exit 1
  fi
}

check_int() { # $1=value $2=name
  case "$1" in
    ''|*[!0-9]*) echo "Error: $2 must be a number of minutes, got '$1'" >&2; exit 1 ;;
  esac
}

check_hhmm() {
  case "$1" in
    [0-2][0-9]:[0-5][0-9]) return 0 ;;
    *) echo "Error: time must be in HH:MM format, got '$1'" >&2; exit 1 ;;
  esac
}

check_targets() {
  case "$1" in
    ''|*[!A-Za-z0-9_,.-]*)
      echo "Error: targets must be comma-separated process name patterns (letters, digits, . _ -), got '$1'" >&2
      exit 1 ;;
  esac
}

# Read today's state (treat stale dates as zero)
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
    targets=$(get targets "$CONFIG");           targets=${targets:-roblox}
    lang=$(get lang "$CONFIG");                 lang=${lang:-auto}
    cpu_th=$(get cpu_threshold "$CONFIG");      cpu_th=${cpu_th:-5}
    read_today_state
    dow=$(date +%u)
    if [ "$dow" -ge 6 ]; then limit_min=$weekend; else limit_min=$weekday; fi
    limit_sec=$(( limit_min * 60 + bonus ))
    remain_sec=$(( limit_sec - used ))
    [ "$remain_sec" -lt 0 ] && remain_sec=0
    # "running" means actively played (CPU activity), matching monitor.sh:
    # Roblox's idle tray-resident process must not show as playing.
    running=0
    if [ -n "$t_user" ]; then
      t_uid=$(id -u "$t_user" 2>/dev/null || echo "")
      if [ -n "$t_uid" ]; then
        pidlist=""
        IFS_BAK="$IFS"; IFS=','
        for pat in $targets; do
          IFS="$IFS_BAK"
          [ -n "$pat" ] || continue
          for pid in $(pgrep -U "$t_uid" -i "$pat" 2>/dev/null); do
            name=$(basename "$(ps -o comm= -p "$pid" 2>/dev/null)" 2>/dev/null)
            case "$name" in PlayCap*|playcap*) continue ;; esac
            pidlist="$pidlist,$pid"
          done
          IFS=','
        done
        IFS="$IFS_BAK"
        pidlist=${pidlist#,}
        if [ -n "$pidlist" ]; then
          running=$(ps -o %cpu= -p "$pidlist" 2>/dev/null \
            | awk -v t="$cpu_th" '{s+=$1} END {print (s>=t ? 1 : 0)}')
        fi
      fi
    fi
    if [ "${2:-}" = "--raw" ]; then
      printf 'enabled=%s\nweekday_limit_min=%s\nweekend_limit_min=%s\nallowed_start=%s\nallowed_end=%s\ntarget_user=%s\ntargets=%s\nlang=%s\ndate=%s\nused_sec=%s\nbonus_sec=%s\nlimit_today_min=%s\nremain_sec=%s\nrunning=%s\n' \
        "$enabled" "$weekday" "$weekend" "$a_start" "$a_end" "$t_user" "$targets" "$lang" \
        "$today" "$used" "$bonus" "$(( limit_sec / 60 ))" "$remain_sec" "$running"
    else
      if [ "$enabled" = "1" ]; then state_txt="ON"; else state_txt="OFF"; fi
      if [ "$running" = "1" ]; then run_txt="running"; else run_txt="not running"; fi
      echo "Limits          : $state_txt"
      echo "Monitored user  : ${t_user:-(not set)}"
      echo "Monitored apps  : $targets ($run_txt)"
      echo "Today           : $(( used / 60 ))min used / $(( limit_sec / 60 ))min limit ($(( remain_sec / 60 ))min left)"
      echo "Limits config   : weekday ${weekday}min / weekend ${weekend}min"
      echo "Allowed hours   : ${a_start}-${a_end}"
      echo "Language        : $lang"
      [ "$bonus" -gt 0 ] && echo "Today's bonus   : +$(( bonus / 60 ))min"
    fi
    ;;
  enable)
    need_write; set_key "$CONFIG" enabled 1; echo "Limits turned ON" ;;
  disable)
    need_write; set_key "$CONFIG" enabled 0; echo "Limits turned OFF" ;;
  set-weekday)
    need_write; check_int "${2:-}" "weekday limit"
    set_key "$CONFIG" weekday_limit_min "$2"; echo "Weekday limit set to $2 min" ;;
  set-weekend)
    need_write; check_int "${2:-}" "weekend limit"
    set_key "$CONFIG" weekend_limit_min "$2"; echo "Weekend limit set to $2 min" ;;
  set-curfew)
    need_write; check_hhmm "${2:-}"; check_hhmm "${3:-}"
    set_key "$CONFIG" allowed_start "$2"
    set_key "$CONFIG" allowed_end "$3"
    echo "Allowed hours set to $2-$3" ;;
  set-targets)
    need_write; check_targets "${2:-}"
    set_key "$CONFIG" targets "$2"; echo "Monitored apps set to: $2" ;;
  set-lang)
    need_write
    case "${2:-}" in
      auto|ja|en) set_key "$CONFIG" lang "$2"; echo "Language set to $2" ;;
      *) echo "Error: lang must be auto, ja, or en" >&2; exit 1 ;;
    esac ;;
  add-bonus)
    need_write; check_int "${2:-}" "bonus minutes"
    read_today_state
    # Rewrite state as today's (prevents the bonus being wiped by the daily reset)
    printf 'date=%s\nused=%s\nbonus=%s\nwarned=0\n' \
      "$today" "$used" "$(( bonus + $2 * 60 ))" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
    chmod 644 "$STATE" 2>/dev/null
    echo "Extended today's limit by $2 min" ;;
  reset-today)
    need_write
    read_today_state
    printf 'date=%s\nused=0\nbonus=%s\nwarned=0\n' "$today" "$bonus" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
    chmod 644 "$STATE" 2>/dev/null
    echo "Today's usage counter reset" ;;
  set-user)
    need_write
    if ! id -u "${2:-}" >/dev/null 2>&1; then
      echo "Error: user '${2:-}' not found" >&2; exit 1
    fi
    set_key "$CONFIG" target_user "$2"; echo "Monitored user set to '$2'" ;;
  -h|--help|help)
    usage ;;
  *)
    usage; exit 1 ;;
esac
