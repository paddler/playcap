#!/bin/bash
# Build the GUI app (CommandLineTools only, no Xcode required)
#
# Note: building happens in a temp dir OUTSIDE the repo. If the repo lives in an
# iCloud-synced folder (Desktop/Documents), File Provider attaches extended
# attributes (com.apple.FinderInfo etc.) to fresh files, which makes codesign
# fail with "resource fork, Finder information, or similar detritus not allowed".
set -eu
cd "$(dirname "$0")"

# Toolchain note: newer Command Line Tools (Swift 6.4+) ship without the SwiftUI
# macro plugin, so bare swiftc cannot compile the GUI there. Until Xcode (or a
# fixed CLT) is installed, reuse the last good build for packaging-only changes:
#   PLAYCAP_SKIP_BUILD=1 ./package.sh
if [ "${PLAYCAP_SKIP_BUILD:-}" = "1" ] && [ -d "dist/PlayCap.app" ]; then
  echo "Reusing existing gui/dist/PlayCap.app (PLAYCAP_SKIP_BUILD=1)"
  exit 0
fi

BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT
APP="$BUILD/PlayCap.app"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -target arm64-apple-macos14.0 -parse-as-library main.swift \
  -o "$APP/Contents/MacOS/PlayCapPanel"
cp Info.plist "$APP/Contents/Info.plist"
xattr -cr "$APP"
codesign --force -s - "$APP"

rm -rf dist
mkdir -p dist
ditto "$APP" "dist/PlayCap.app"

echo "Built: gui/dist/PlayCap.app"
