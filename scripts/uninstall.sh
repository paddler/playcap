#!/bin/bash
# PlayCap uninstaller
# Usage: sudo ./uninstall.sh           (keeps the usage history log)
#        sudo ./uninstall.sh --purge   (removes everything)
set -u

APP_DIR="/Library/Application Support/PlayCap"
LIBEXEC="/usr/local/libexec/playcap"
PLIST="/Library/LaunchDaemons/com.nabehiro.playcap.plist"

if [ "$(id -u)" != "0" ]; then
  echo "Error: please run with sudo: sudo ./uninstall.sh"
  echo "エラー: sudo を付けて実行してください: sudo ./uninstall.sh"
  exit 1
fi

launchctl bootout system "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
rm -f /usr/local/bin/playcap
rm -rf "$LIBEXEC"
rm -rf "/Applications/PlayCap.app"

if [ "${1:-}" = "--purge" ]; then
  rm -rf "$APP_DIR"
  echo "Uninstalled (settings and history removed) / 完全に削除しました"
else
  rm -f "$APP_DIR/config" "$APP_DIR/state" "$APP_DIR/state.tmp" "$APP_DIR/daemon.log"
  echo "Uninstalled. Usage history kept at $APP_DIR/usage.log (use --purge to remove)"
  echo "アンインストール完了（使用履歴は残しました。不要なら --purge で実行）"
fi
