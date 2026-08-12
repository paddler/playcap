#!/bin/bash
# 配布物 RobloxLimit-installer.zip を作成（開発機で実行）
set -eu
cd "$(dirname "$0")"

./gui/build.sh

PKG="dist/RobloxLimit"
rm -rf dist
mkdir -p "$PKG/scripts" "$PKG/daemon"

cp scripts/monitor.sh scripts/ctl.sh "$PKG/scripts/"
cp scripts/install.sh scripts/uninstall.sh "$PKG/"
cp daemon/com.nabehiro.robloxlimit.plist "$PKG/daemon/"
cp -R "gui/dist/Roblox Limit.app" "$PKG/"
cp INSTALL.md "$PKG/"
chmod +x "$PKG"/*.sh "$PKG/scripts/"*.sh

(cd dist && zip -qry RobloxLimit-installer.zip RobloxLimit)
echo "作成完了: dist/RobloxLimit-installer.zip"
