#!/bin/bash
# Build the distributable zip: dist/PlayCap-installer.zip
set -eu
cd "$(dirname "$0")"

./gui/build.sh

PKG="dist/PlayCap"
rm -rf dist
mkdir -p "$PKG/scripts" "$PKG/daemon"

cp scripts/monitor.sh scripts/ctl.sh "$PKG/scripts/"
cp scripts/install.sh scripts/uninstall.sh "$PKG/"
cp installer/Install.command installer/Uninstall.command "$PKG/"
cp daemon/com.nabehiro.playcap.plist "$PKG/daemon/"
cp -R "gui/dist/PlayCap.app" "$PKG/"
cp INSTALL.en.md INSTALL.ja.md "$PKG/"
scripts/build_guides.sh "$PKG"
chmod +x "$PKG"/*.sh "$PKG"/*.command "$PKG/scripts/"*.sh

(cd dist && zip -qry PlayCap-installer.zip PlayCap)
echo "Created: dist/PlayCap-installer.zip"
