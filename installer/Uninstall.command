#!/bin/bash
# PlayCap - double-click uninstaller
cd "$(dirname "$0")"
echo "============================================"
echo " PlayCap Uninstaller"
echo " Administrator password will be required."
echo " 管理者パスワードの入力が必要です。"
echo "============================================"
echo ""
sudo ./uninstall.sh
echo ""
echo "Press Enter to close this window / Enter キーで閉じます"
read -r _
