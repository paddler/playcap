#!/bin/bash
# PlayCap - monitor daemon core
# Runs once per tick (every 30s) from launchd as root.
#
# Testing: set PLAYCAP_DIR to override the data directory and run without root
# (notifications then go to the current session directly).
set -u

APP_DIR="${PLAYCAP_DIR:-/Library/Application Support/PlayCap}"
CONFIG="$APP_DIR/config"
STATE="$APP_DIR/state"
USAGE_LOG="$APP_DIR/usage.log"
TICK="${PLAYCAP_TICK:-30}"

[ -r "$CONFIG" ] || exit 0

# ---- load config (key=value) ----
enabled=1
weekday_limit_min=120
weekend_limit_min=180
allowed_start="07:00"
allowed_end="21:00"
target_user=""
targets="roblox"
lang="auto"
cpu_threshold=5
while IFS='=' read -r k v; do
  case "$k" in
    enabled)            enabled="$v" ;;
    weekday_limit_min)  weekday_limit_min="$v" ;;
    weekend_limit_min)  weekend_limit_min="$v" ;;
    allowed_start)      allowed_start="$v" ;;
    allowed_end)        allowed_end="$v" ;;
    target_user)        target_user="$v" ;;
    targets)            targets="$v" ;;
    lang)               lang="$v" ;;
    cpu_threshold)      cpu_threshold="$v" ;;
  esac
done < "$CONFIG"

[ "$enabled" = "1" ] || exit 0
[ -n "$target_user" ] || exit 0
uid=$(id -u "$target_user" 2>/dev/null) || exit 0

# ---- load state ----
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

# On date change: append yesterday's total to history, then reset
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

# ---- detect monitored processes ----
# Match by process name only (never -f: URL arguments in browsers would false-match).
# Exclude PlayCap's own components so a broad user pattern can't kill the GUI.
collect_pids() {
  local pat pid name result=""
  local IFS_BAK="$IFS"
  IFS=','
  for pat in $targets; do
    IFS="$IFS_BAK"
    [ -n "$pat" ] || continue
    for pid in $(pgrep -U "$uid" -i "$pat" 2>/dev/null); do
      name=$(basename "$(ps -o comm= -p "$pid" 2>/dev/null)" 2>/dev/null)
      case "$name" in
        PlayCap*|playcap*) continue ;;
      esac
      result="$result $pid"
    done
    IFS=','
  done
  IFS="$IFS_BAK"
  echo "$result" | tr ' ' '\n' | grep -v '^$' | sort -u
}

pids=$(collect_pids)
if [ -z "$pids" ]; then
  save_state
  exit 0
fi

# ---- activity check: count (and enforce) only during actual play ----
# Roblox keeps a resident "RobloxPlayer -launchToTray" process after the window
# is closed. An idle tray process must not consume the daily budget, so a tick
# only counts when the matched processes show real CPU activity. Gameplay runs
# at tens of percent CPU; the idle tray sits at ~0%.
pidlist=$(echo "$pids" | tr '\n' ',' | sed 's/,$//')
active=$(ps -o %cpu= -p "$pidlist" 2>/dev/null \
  | awk -v t="$cpu_threshold" '{s+=$1} END {print (s>=t ? 1 : 0)}')
if [ "$active" != "1" ]; then
  save_state
  exit 0
fi

used=$(( used + TICK ))

# ---- language resolution (auto = target user's macOS locale) ----
if [ "$lang" = "auto" ]; then
  if [ "$(id -u)" = "$uid" ]; then
    loc=$(defaults read -g AppleLocale 2>/dev/null || echo "en")
  else
    loc=$(launchctl asuser "$uid" sudo -u "$target_user" defaults read -g AppleLocale 2>/dev/null || echo "en")
  fi
  case "$loc" in ja*) lang="ja" ;; *) lang="en" ;; esac
fi

msg() { # $1 = message key
  if [ "$lang" = "ja" ]; then
    case "$1" in
      curfew) echo "いまは使えない時間です（つかえるのは ${allowed_start}〜${allowed_end}）" ;;
      timeup) echo "今日のゲーム時間はおしまい！また明日ね" ;;
      min1)   echo "残り1分！セーブしてね" ;;
      min5)   echo "あと5分でおわりです" ;;
      min10)  echo "あと10分でおわりです" ;;
    esac
  else
    case "$1" in
      curfew) echo "Game time is not allowed right now (allowed: ${allowed_start}-${allowed_end})" ;;
      timeup) echo "Game time is over for today. See you tomorrow!" ;;
      min1)   echo "1 minute left! Save your game now" ;;
      min5)   echo "5 minutes left" ;;
      min10)  echo "10 minutes left" ;;
    esac
  fi
}

notify() { # $1 = message key
  local text
  text=$(msg "$1")
  if [ "$(id -u)" = "$uid" ]; then
    /usr/bin/osascript -e "display notification \"$text\" with title \"PlayCap\" sound name \"Glass\"" >/dev/null 2>&1 || true
  else
    launchctl asuser "$uid" sudo -u "$target_user" \
      /usr/bin/osascript -e "display notification \"$text\" with title \"PlayCap\" sound name \"Glass\"" >/dev/null 2>&1 || true
  fi
}

kill_targets() {
  # shellcheck disable=SC2086
  kill -9 $pids 2>/dev/null || true
}

hm_to_min() { echo $(( 10#${1%%:*} * 60 + 10#${1##*:} )); }

# ---- curfew check (outside allowed window -> terminate) ----
now_min=$(( 10#$(date +%H) * 60 + 10#$(date +%M) ))
start_min=$(hm_to_min "$allowed_start")
end_min=$(hm_to_min "$allowed_end")
if [ "$now_min" -lt "$start_min" ] || [ "$now_min" -ge "$end_min" ]; then
  notify curfew
  kill_targets
  save_state
  exit 0
fi

# ---- daily limit check (weekday/weekend + today's bonus) ----
dow=$(date +%u)   # 1=Mon ... 6=Sat 7=Sun
if [ "$dow" -ge 6 ]; then
  limit_sec=$(( weekend_limit_min * 60 + bonus ))
else
  limit_sec=$(( weekday_limit_min * 60 + bonus ))
fi

# remaining = min(remaining by limit, remaining until curfew end)
remain=$(( limit_sec - used ))
remain_curfew=$(( (end_min - now_min) * 60 ))
[ "$remain_curfew" -lt "$remain" ] && remain=$remain_curfew

if [ "$remain" -le 0 ]; then
  notify timeup
  kill_targets
elif [ "$remain" -le 60 ]; then
  if [ "$warned" -lt 3 ]; then notify min1; warned=3; fi
elif [ "$remain" -le 300 ]; then
  if [ "$warned" -lt 2 ]; then notify min5; warned=2; fi
elif [ "$remain" -le 600 ]; then
  if [ "$warned" -lt 1 ]; then notify min10; warned=1; fi
else
  warned=0   # remaining went back up (e.g. bonus added) -> reset warning stage
fi

save_state
exit 0
