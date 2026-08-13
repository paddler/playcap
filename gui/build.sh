#!/bin/bash
# Build the GUI app (CommandLineTools only, no Xcode required)
set -eu
cd "$(dirname "$0")"

APP="dist/PlayCap.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS"

swiftc -O -target arm64-apple-macos14.0 -parse-as-library main.swift \
  -o "$APP/Contents/MacOS/PlayCapPanel"
cp Info.plist "$APP/Contents/Info.plist"
xattr -cr "$APP"
codesign --force -s - "$APP"

echo "Built: gui/$APP"
