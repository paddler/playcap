#!/bin/bash
# GUI アプリのビルド（開発機で実行。CommandLineTools のみで動く / Xcode 不要）
set -eu
cd "$(dirname "$0")"

APP="dist/Roblox Limit.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS"

swiftc -O -target arm64-apple-macos14.0 -parse-as-library main.swift \
  -o "$APP/Contents/MacOS/LimitPanel"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force -s - "$APP"

echo "ビルド完了: gui/$APP"
