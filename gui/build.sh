#!/bin/bash
# Build the GUI app (CommandLineTools only, no Xcode required)
#
# Note: building happens in a temp dir OUTSIDE the repo. If the repo lives in an
# iCloud-synced folder (Desktop/Documents), File Provider attaches extended
# attributes (com.apple.FinderInfo etc.) to fresh files, which makes codesign
# fail with "resource fork, Finder information, or similar detritus not allowed".
set -eu
cd "$(dirname "$0")"

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
