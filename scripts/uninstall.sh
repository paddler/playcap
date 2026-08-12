#!/bin/bash
# Roblox Limit - アンインストーラ
# 使い方: sudo ./uninstall.sh          （使用履歴 usage.log は残す）
#         sudo ./uninstall.sh --purge  （データも含め完全削除）
set -u

APP_DIR="/Library/Application Support/RobloxLimit"
LIBEXEC="/usr/local/libexec/roblox-limit"
PLIST="/Library/LaunchDaemons/com.nabehiro.robloxlimit.plist"

if [ "$(id -u)" != "0" ]; then
  echo "エラー: sudo を付けて実行してください: sudo ./uninstall.sh" >&2
  exit 1
fi

launchctl bootout system "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
rm -f /usr/local/bin/roblox-limit
rm -rf "$LIBEXEC"
rm -rf "/Applications/Roblox Limit.app"

if [ "${1:-}" = "--purge" ]; then
  rm -rf "$APP_DIR"
  echo "アンインストール完了（設定・履歴も削除しました）"
else
  rm -f "$APP_DIR/config" "$APP_DIR/state" "$APP_DIR/state.tmp" "$APP_DIR/daemon.log"
  echo "アンインストール完了（使用履歴 $APP_DIR/usage.log は残しました。不要なら --purge で実行）"
fi
