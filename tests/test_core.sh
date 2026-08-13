#!/bin/bash
# PlayCap core logic tests - run WITHOUT root using PLAYCAP_DIR override.
# Fake game processes are compiled locally (copies of system binaries get
# SIGKILLed by AMFI on Apple Silicon, so never use cp /bin/sleep).
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK=$(mktemp -d)
trap 'pkill -9 -U "$(id -u)" -i fakegame 2>/dev/null; kill -9 ${FAKE_PIDS:-} 2>/dev/null; rm -rf "$WORK"' EXIT

export PLAYCAP_DIR="$WORK/data"
export PLAYCAP_TICK=30

MON="$REPO/scripts/monitor.sh"
CTL="$REPO/scripts/ctl.sh"

pass=0; fail=0
check() { # $1=description $2=condition(0=OK)
  if [ "$2" = "0" ]; then echo "  PASS: $1"; pass=$((pass+1));
  else echo "  FAIL: $1"; fail=$((fail+1)); fi
}

mkdir -p "$PLAYCAP_DIR"

# Fake game binaries (self-compiled)
printf '#include <unistd.h>\nint main(void){ sleep(600); return 0; }\n' > "$WORK/fake.c"
clang -o "$WORK/RobloxPlayer" "$WORK/fake.c"
cp "$WORK/RobloxPlayer" "$WORK/MinecraftGame"
cp "$WORK/RobloxPlayer" "$WORK/PlayCapPanel"

FAKE_PIDS=""
start_fake() { # $1=binary name -> sets LAST_PID
  "$WORK/$1" &
  LAST_PID=$!
  FAKE_PIDS="$FAKE_PIDS $LAST_PID"
  sleep 0.3
}
stop_all() { kill -9 $FAKE_PIDS 2>/dev/null; FAKE_PIDS=""; sleep 0.2; true; }

get_state() { grep "^$1=" "$PLAYCAP_DIR/state" | cut -d= -f2; }

write_config() { # $1=extra lines (optional)
  cat > "$PLAYCAP_DIR/config" <<EOF
enabled=1
weekday_limit_min=120
weekend_limit_min=180
allowed_start=00:00
allowed_end=23:59
lang=en
target_user=$(whoami)
targets=roblox
EOF
  [ -n "${1:-}" ] && echo "$1" >> "$PLAYCAP_DIR/config"
  true
}

echo "=== Test 1: counts while game is running ==="
write_config
start_fake RobloxPlayer; RB_PID=$LAST_PID
bash "$MON"; bash "$MON"; bash "$MON"
used=$(get_state used)
check "3 ticks -> used=90 (got: $used)" "$([ "$used" = "90" ]; echo $?)"
kill -0 "$RB_PID" 2>/dev/null
check "process survives under the limit" "$?"

echo "=== Test 2: no counting while stopped ==="
stop_all
bash "$MON"
used=$(get_state used)
check "used stays 90 (got: $used)" "$([ "$used" = "90" ]; echo $?)"

echo "=== Test 3: killed when over the limit ==="
start_fake RobloxPlayer; RB_PID=$LAST_PID
sed -i '' 's/^used=.*/used=7180/' "$PLAYCAP_DIR/state"
bash "$MON"   # +30 -> 7210 > 7200 -> kill
sleep 0.5
kill -0 "$RB_PID" 2>/dev/null
check "killed over the limit" "$([ "$?" != "0" ]; echo $?)"

echo "=== Test 4: warning stage transitions ==="
rm -f "$PLAYCAP_DIR/state"
start_fake RobloxPlayer
bash "$MON"
w=$(get_state warned)
check "plenty left -> warned=0 (got: $w)" "$([ "$w" = "0" ]; echo $?)"
sed -i '' 's/^used=.*/used=6630/' "$PLAYCAP_DIR/state"
bash "$MON"  # used=6660, remain=540s (9min) -> 10min band
w=$(get_state warned)
check "9min left -> warned=1 (got: $w)" "$([ "$w" = "1" ]; echo $?)"
sed -i '' 's/^used=.*/used=6960/' "$PLAYCAP_DIR/state"
bash "$MON"  # used=6990, remain=210s -> 5min band
w=$(get_state warned)
check "3.5min left -> warned=2 (got: $w)" "$([ "$w" = "2" ]; echo $?)"
stop_all

echo "=== Test 5: killed outside allowed hours ==="
rm -f "$PLAYCAP_DIR/state"
write_config
sed -i '' 's/^allowed_end=.*/allowed_end=00:01/' "$PLAYCAP_DIR/config"
start_fake RobloxPlayer; RB_PID=$LAST_PID
bash "$MON"
sleep 0.5
kill -0 "$RB_PID" 2>/dev/null
check "killed outside curfew window" "$([ "$?" != "0" ]; echo $?)"
stop_all

echo "=== Test 6: daily reset + history log ==="
write_config
printf 'date=2026-08-11\nused=5400\nbonus=600\nwarned=2\n' > "$PLAYCAP_DIR/state"
bash "$MON"
d=$(get_state date); u=$(get_state used); b=$(get_state bonus)
check "date updated to today (got: $d)" "$([ "$d" = "$(date +%F)" ]; echo $?)"
check "used reset (got: $u)" "$([ "$u" = "0" ]; echo $?)"
check "bonus reset (got: $b)" "$([ "$b" = "0" ]; echo $?)"
grep -q "2026-08-11 used_min=90" "$PLAYCAP_DIR/usage.log"
check "yesterday logged to usage.log" "$?"

echo "=== Test 7: disabled -> no-op ==="
start_fake RobloxPlayer; RB_PID=$LAST_PID
sed -i '' 's/^enabled=.*/enabled=0/' "$PLAYCAP_DIR/config"
before=$(get_state used)
bash "$MON"
after=$(get_state used)
kill -0 "$RB_PID" 2>/dev/null
alive=$?
check "no counting, no kill while OFF (used: $before->$after, alive=$alive)" \
  "$([ "$before" = "$after" ] && [ "$alive" = "0" ]; echo $?)"
stop_all

echo "=== Test 8: multiple targets ==="
rm -f "$PLAYCAP_DIR/state"
write_config
sed -i '' 's/^targets=.*/targets=roblox,minecraft/' "$PLAYCAP_DIR/config"
start_fake MinecraftGame; MC_PID=$LAST_PID
bash "$MON"
used=$(get_state used)
check "minecraft pattern counts too (used=$used)" "$([ "$used" = "30" ]; echo $?)"
sed -i '' 's/^used=.*/used=7200/' "$PLAYCAP_DIR/state"
bash "$MON"
sleep 0.5
kill -0 "$MC_PID" 2>/dev/null
check "minecraft process killed over limit" "$([ "$?" != "0" ]; echo $?)"
stop_all

echo "=== Test 9: PlayCap's own processes are excluded ==="
rm -f "$PLAYCAP_DIR/state"
write_config
sed -i '' 's/^targets=.*/targets=playcap/' "$PLAYCAP_DIR/config"
start_fake PlayCapPanel; GUI_PID=$LAST_PID
bash "$MON"
used=$(get_state used)
kill -0 "$GUI_PID" 2>/dev/null
alive=$?
check "PlayCapPanel neither counted nor killed (used=$used, alive=$alive)" \
  "$([ "$used" = "0" ] && [ "$alive" = "0" ]; echo $?)"
stop_all

echo "=== Test 10: ctl.sh commands ==="
write_config
bash "$CTL" status --raw | grep -q "^enabled=1"
check "status --raw returns enabled=1" "$?"
bash "$CTL" status --raw | grep -q "^targets=roblox"
check "status --raw returns targets" "$?"
bash "$CTL" set-weekday 90 >/dev/null
grep -q "^weekday_limit_min=90" "$PLAYCAP_DIR/config"
check "set-weekday 90 applied" "$?"
bash "$CTL" set-curfew 08:00 20:30 >/dev/null
grep -q "^allowed_end=20:30" "$PLAYCAP_DIR/config"
check "set-curfew applied" "$?"
bash "$CTL" set-targets roblox,minecraft >/dev/null
grep -q "^targets=roblox,minecraft" "$PLAYCAP_DIR/config"
check "set-targets applied" "$?"
bash "$CTL" set-targets 'bad;rm -rf' 2>/dev/null
check "set-targets rejects shell metacharacters" "$([ "$?" != "0" ]; echo $?)"
bash "$CTL" set-lang en >/dev/null
grep -q "^lang=en" "$PLAYCAP_DIR/config"
check "set-lang applied" "$?"
bash "$CTL" set-lang fr 2>/dev/null
check "set-lang rejects unsupported language" "$([ "$?" != "0" ]; echo $?)"
bash "$CTL" add-bonus 30 >/dev/null
b=$(get_state bonus)
check "add-bonus 30 -> bonus=1800 (got: $b)" "$([ "$b" = "1800" ]; echo $?)"
bash "$CTL" set-weekday abc 2>/dev/null
check "set-weekday rejects non-numeric" "$([ "$?" != "0" ]; echo $?)"

echo ""
echo "==== RESULT: PASS=$pass FAIL=$fail ===="
[ "$fail" = "0" ]
