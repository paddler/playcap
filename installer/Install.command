#!/bin/bash
# PlayCap - double-click installer
cd "$(dirname "$0")"
echo "============================================"
echo " PlayCap Installer"
echo " Administrator password will be required."
echo " 管理者パスワードの入力が必要です。"
echo "============================================"
echo ""
if [ ! -f "./install.sh" ]; then
  echo "This folder is the SOURCE REPOSITORY (e.g. playcap-main from GitHub),"
  echo "not the packaged installer. Please use the packaged PlayCap-installer.zip,"
  echo "or build one from the repo root with: ./package.sh"
  echo ""
  echo "このフォルダは開発者向けのソースコード版です（GitHub の playcap-main 等）。"
  echo "配布用パッケージ PlayCap-installer.zip を展開した「PlayCap」フォルダから"
  echo "実行してください（自分でビルドする場合はリポジトリ直下で ./package.sh）。"
  echo ""
  echo "Press Enter to close this window / Enter キーで閉じます"
  read -r _
  exit 1
fi
sudo ./install.sh
echo ""
echo "Press Enter to close this window / Enter キーで閉じます"
read -r _
