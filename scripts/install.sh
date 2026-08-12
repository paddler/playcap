#!/bin/bash
# Roblox Limit - インストーラ（息子さんの Mac で、親の管理者アカウントから実行する）
# 使い方: sudo ./install.sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="/Library/Application Support/RobloxLimit"
LIBEXEC="/usr/local/libexec/roblox-limit"
PLIST_DST="/Library/LaunchDaemons/com.nabehiro.robloxlimit.plist"
LABEL="com.nabehiro.robloxlimit"

if [ "$(id -u)" != "0" ]; then
  echo "エラー: sudo を付けて実行してください: sudo ./install.sh" >&2
  exit 1
fi

# パッケージ内のファイル位置（zip 展開後のレイアウト）
find_src() { # $1=相対パス候補1 $2=候補2
  if [ -e "$SCRIPT_DIR/$1" ]; then echo "$SCRIPT_DIR/$1"
  elif [ -e "$SCRIPT_DIR/$2" ]; then echo "$SCRIPT_DIR/$2"
  else echo ""; fi
}
MONITOR_SRC=$(find_src "scripts/monitor.sh" "monitor.sh")
CTL_SRC=$(find_src "scripts/ctl.sh" "ctl.sh")
PLIST_SRC=$(find_src "daemon/com.nabehiro.robloxlimit.plist" "com.nabehiro.robloxlimit.plist")
GUI_SRC=$(find_src "Roblox Limit.app" "gui/dist/Roblox Limit.app")

if [ -z "$MONITOR_SRC" ] || [ -z "$CTL_SRC" ] || [ -z "$PLIST_SRC" ]; then
  echo "エラー: パッケージ内に必要ファイルが見つかりません（zip を丸ごと展開したフォルダで実行してください）" >&2
  exit 1
fi

echo "=== Roblox Limit インストーラ ==="
echo "この Mac: $(sw_vers -productName) $(sw_vers -productVersion) / $(uname -m)"
echo ""

# ---- 対象アカウントの選択 ----
echo "この Mac のユーザー一覧:"
candidates=$(dscl . -list /Users | grep -v '^_' | grep -Ev '^(root|daemon|nobody)$')
echo "$candidates" | sed 's/^/  - /'
echo ""
printf "お子さんのアカウント名を入力してください: "
read -r target_user

if ! id -u "$target_user" >/dev/null 2>&1; then
  echo "エラー: ユーザー '$target_user' が見つかりません" >&2
  exit 1
fi

# ---- 標準ユーザー（非管理者）であることを確認 ----
if dseditgroup -o checkmember -m "$target_user" admin >/dev/null 2>&1; then
  cat >&2 <<EOF

エラー: '$target_user' は管理者アカウントです。このままでは本人が制限を解除できてしまいます。

先に「システム設定 > ユーザとグループ > $target_user」を開き、
「このユーザにこのコンピュータの管理を許可」のチェックを外して標準ユーザーにしてから、
もう一度 install.sh を実行してください（データは消えません）。
EOF
  exit 1
fi
echo "OK: '$target_user' は標準ユーザーです"

# ---- ファイル配置 ----
mkdir -p "$APP_DIR" "$LIBEXEC" /usr/local/bin
install -m 755 -o root -g wheel "$MONITOR_SRC" "$LIBEXEC/monitor.sh"
install -m 755 -o root -g wheel "$CTL_SRC" "$LIBEXEC/ctl.sh"
ln -sf "$LIBEXEC/ctl.sh" /usr/local/bin/roblox-limit

# 設定: 既存があれば残す（再インストール/更新時に設定を保持）。target_user だけ更新
if [ ! -f "$APP_DIR/config" ]; then
  cat > "$APP_DIR/config" <<EOF
enabled=1
weekday_limit_min=120
weekend_limit_min=180
allowed_start=07:00
allowed_end=21:00
target_user=$target_user
EOF
  echo "デフォルト設定を作成しました（平日120分 / 休日180分 / 07:00〜21:00）"
else
  "$LIBEXEC/ctl.sh" set-user "$target_user" >/dev/null
  echo "既存の設定を保持しました（対象アカウントのみ更新）"
fi
chown root:wheel "$APP_DIR" "$APP_DIR/config"
chmod 755 "$APP_DIR"
chmod 644 "$APP_DIR/config"

# ---- GUI アプリ ----
if [ -n "$GUI_SRC" ]; then
  rm -rf "/Applications/Roblox Limit.app"
  cp -R "$GUI_SRC" "/Applications/Roblox Limit.app"
  chown -R root:wheel "/Applications/Roblox Limit.app"
  # AirDrop/ダウンロード経由の quarantine 属性を除去（自作アプリなので Gatekeeper 警告を回避）
  xattr -dr com.apple.quarantine "/Applications/Roblox Limit.app" 2>/dev/null || true
  echo "GUI を /Applications/Roblox Limit.app に配置しました"
fi

# ---- デーモン登録 ----
install -m 644 -o root -g wheel "$PLIST_SRC" "$PLIST_DST"
launchctl bootout system "$PLIST_DST" 2>/dev/null || true
launchctl bootstrap system "$PLIST_DST"

echo ""
echo "=== インストール完了 ==="
launchctl print "system/$LABEL" >/dev/null 2>&1 && echo "デーモン: 稼働中（30秒ごとに監視）"
echo ""
"$LIBEXEC/ctl.sh" status
echo ""
echo "設定変更: /Applications/Roblox Limit.app を開く、または sudo roblox-limit --help"
