#!/bin/bash
# PlayCap installer - run on the child's Mac from a PARENT ADMIN account.
# Usage: sudo ./install.sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="/Library/Application Support/PlayCap"
LIBEXEC="/usr/local/libexec/playcap"
PLIST_DST="/Library/LaunchDaemons/com.nabehiro.playcap.plist"
LABEL="com.nabehiro.playcap"

# Legacy (pre-rename RobloxLimit) install locations, migrated automatically
OLD_APP_DIR="/Library/Application Support/RobloxLimit"
OLD_PLIST="/Library/LaunchDaemons/com.nabehiro.robloxlimit.plist"
OLD_LIBEXEC="/usr/local/libexec/roblox-limit"

if [ "$(id -u)" != "0" ]; then
  echo "Error: please run with sudo: sudo ./install.sh"
  echo "エラー: sudo を付けて実行してください: sudo ./install.sh"
  exit 1
fi

find_src() { # $1=candidate1 $2=candidate2
  if [ -e "$SCRIPT_DIR/$1" ]; then echo "$SCRIPT_DIR/$1"
  elif [ -e "$SCRIPT_DIR/$2" ]; then echo "$SCRIPT_DIR/$2"
  else echo ""; fi
}
MONITOR_SRC=$(find_src "scripts/monitor.sh" "monitor.sh")
CTL_SRC=$(find_src "scripts/ctl.sh" "ctl.sh")
PLIST_SRC=$(find_src "daemon/com.nabehiro.playcap.plist" "com.nabehiro.playcap.plist")
GUI_SRC=$(find_src "PlayCap.app" "gui/dist/PlayCap.app")

if [ -z "$MONITOR_SRC" ] || [ -z "$CTL_SRC" ] || [ -z "$PLIST_SRC" ]; then
  echo "Error: package files missing. Run this from the fully extracted PlayCap folder."
  echo "エラー: 必要ファイルが見つかりません。zip を丸ごと展開したフォルダで実行してください。"
  exit 1
fi

echo "=== PlayCap Installer ==="
echo "This Mac: $(sw_vers -productName) $(sw_vers -productVersion) / $(uname -m)"
echo ""

# ---- choose the child's account ----
echo "User accounts on this Mac / この Mac のユーザー一覧:"
candidates=$(dscl . -list /Users | grep -v '^_' | grep -Ev '^(root|daemon|nobody)$')
echo "$candidates" | sed 's/^/  - /'
echo ""
printf "Enter the CHILD's account name / お子さんのアカウント名を入力: "
read -r target_user

if ! id -u "$target_user" >/dev/null 2>&1; then
  echo "Error: user '$target_user' not found / ユーザーが見つかりません"
  exit 1
fi

# ---- the child must be a STANDARD (non-admin) user ----
if dseditgroup -o checkmember -m "$target_user" admin >/dev/null 2>&1; then
  cat <<EOF

Error: '$target_user' is an ADMINISTRATOR. They could disable PlayCap themselves.
Open System Settings > Users & Groups > $target_user and turn OFF
"Allow this user to administer this computer", then run install.sh again.
(No data is lost by this change.)

エラー: '$target_user' は管理者です。本人が制限を解除できてしまいます。
「システム設定 > ユーザとグループ」で管理者権限を外して標準ユーザーにしてから
もう一度実行してください（データは消えません）。
EOF
  exit 1
fi
echo "OK: '$target_user' is a standard user / 標準ユーザーです"

# ---- remove legacy RobloxLimit install (if present) ----
if [ -f "$OLD_PLIST" ] || [ -d "$OLD_LIBEXEC" ]; then
  echo "Migrating from previous RobloxLimit install... / 旧 RobloxLimit から移行します..."
  launchctl bootout system "$OLD_PLIST" 2>/dev/null || true
  rm -f "$OLD_PLIST" /usr/local/bin/roblox-limit
  rm -rf "$OLD_LIBEXEC" "/Applications/Roblox Limit.app"
fi

# ---- install files ----
mkdir -p "$APP_DIR" "$LIBEXEC" /usr/local/bin
install -m 755 -o root -g wheel "$MONITOR_SRC" "$LIBEXEC/monitor.sh"
install -m 755 -o root -g wheel "$CTL_SRC" "$LIBEXEC/ctl.sh"
ln -sf "$LIBEXEC/ctl.sh" /usr/local/bin/playcap

# Config: keep existing settings on reinstall/update; migrate legacy config if found
if [ ! -f "$APP_DIR/config" ]; then
  if [ -f "$OLD_APP_DIR/config" ]; then
    cp "$OLD_APP_DIR/config" "$APP_DIR/config"
    grep -q '^targets=' "$APP_DIR/config" || echo "targets=roblox" >> "$APP_DIR/config"
    grep -q '^lang=' "$APP_DIR/config" || echo "lang=auto" >> "$APP_DIR/config"
    [ -f "$OLD_APP_DIR/usage.log" ] && cp "$OLD_APP_DIR/usage.log" "$APP_DIR/usage.log"
    echo "Migrated previous settings / 旧設定を引き継ぎました"
  else
    cat > "$APP_DIR/config" <<EOF
enabled=1
weekday_limit_min=120
weekend_limit_min=180
allowed_start=07:00
allowed_end=21:00
targets=roblox
lang=auto
target_user=$target_user
EOF
    echo "Created default config (weekday 120min / weekend 180min / 07:00-21:00)"
    echo "デフォルト設定を作成（平日120分 / 休日180分 / 07:00〜21:00）"
  fi
fi
"$LIBEXEC/ctl.sh" set-user "$target_user" >/dev/null
chown root:wheel "$APP_DIR" "$APP_DIR/config"
chmod 755 "$APP_DIR"
chmod 644 "$APP_DIR/config"

# ---- GUI app ----
if [ -n "$GUI_SRC" ]; then
  rm -rf "/Applications/PlayCap.app"
  cp -R "$GUI_SRC" "/Applications/PlayCap.app"
  chown -R root:wheel "/Applications/PlayCap.app"
  # Strip quarantine (AirDrop/download) so the self-built app opens without Gatekeeper blocking
  xattr -dr com.apple.quarantine "/Applications/PlayCap.app" 2>/dev/null || true
  echo "GUI installed to /Applications/PlayCap.app"
fi

# ---- register daemon ----
install -m 644 -o root -g wheel "$PLIST_SRC" "$PLIST_DST"
launchctl bootout system "$PLIST_DST" 2>/dev/null || true
launchctl bootstrap system "$PLIST_DST"

echo ""
echo "=== Install complete / インストール完了 ==="
launchctl print "system/$LABEL" >/dev/null 2>&1 && echo "Daemon: running (checks every 30s) / 稼働中"
echo ""
"$LIBEXEC/ctl.sh" status
echo ""
echo "Settings: open /Applications/PlayCap.app, or run: sudo playcap --help"
echo "設定変更: /Applications/PlayCap.app を開く、または sudo playcap --help"
