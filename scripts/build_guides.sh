#!/bin/bash
# Generate self-contained HTML setup guides (en/ja) with embedded screenshots.
# Usage: build_guides.sh <output_dir>   (called by package.sh at packaging time)
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?output dir required}"
mkdir -p "$OUT"

IMG_EN=$(base64 -i "$REPO/docs/screenshots/gui-en.png")
IMG_JA=$(base64 -i "$REPO/docs/screenshots/gui-ja.png")

CSS='body{font-family:-apple-system,"Hiragino Sans",sans-serif;max-width:760px;margin:40px auto;padding:0 24px;line-height:1.8;color:#1c1c1e}
h1{border-bottom:3px solid #34c759;padding-bottom:8px}h2{margin-top:2em;border-left:5px solid #34c759;padding-left:10px}
code,pre{background:#f2f2f7;border-radius:6px;font-family:ui-monospace,Menlo,monospace}
pre{padding:14px;overflow-x:auto}code{padding:2px 6px}
.tip{background:#eafaf0;border:1px solid #34c759;border-radius:8px;padding:12px 16px;margin:14px 0}
.warn{background:#fff8e6;border:1px solid #e6a700;border-radius:8px;padding:12px 16px;margin:14px 0}
img.shot{max-width:440px;width:100%;border:1px solid #ddd;border-radius:10px;margin:10px 0}
ol li{margin:8px 0}'

cat > "$OUT/Setup Guide (English).html" <<EOF
<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<title>PlayCap Setup Guide</title><style>${CSS}</style></head><body>
<h1>PlayCap Setup Guide</h1>
<p>Takes about 10 minutes. Log in to your child's Mac with a <b>parent administrator account</b>.</p>
<h2>1. Before you start</h2>
<ol>
<li>Your child's account must be a <b>Standard user</b>. Check: System Settings &gt; Users &amp; Groups. If it says Admin, turn off "Allow this user to administer this computer" (no data is lost).</li>
<li>The installer double-checks this and stops with instructions if needed.</li>
</ol>
<h2>2. Install</h2>
<ol>
<li>Copy this whole extracted <b>PlayCap</b> folder to the child's Mac (AirDrop, USB, shared folder).</li>
<li>Double-click <b>Install.command</b>.<div class="warn">If macOS says it "cannot be opened": right-click the file &gt; <b>Open</b> &gt; <b>Open</b> again. This happens once because the package is not notarized by Apple yet.</div></li>
<li>Enter the administrator password when asked.</li>
<li>Type your child's account name when the user list appears.</li>
<li>"Install complete" appears with the current settings. Done!</li>
</ol>
<p>Defaults: <b>120 min weekdays / 180 min weekends / allowed 07:00-21:00</b></p>
<h2>3. First-time test (5 minutes)</h2>
<ol>
<li>Open <b>PlayCap</b> from Applications and temporarily set both daily limits to 2 minutes (admin password required).</li>
<li>Switch to your child's account, start Roblox: <b>it should quit automatically after about 2 minutes</b>. Allow notifications if macOS asks.</li>
<li>Switch back and restore your real limits.</li>
</ol>
<h2>4. Daily use</h2>
<p>This is the parent control panel (Applications &gt; PlayCap). Viewing is open to everyone; <b>saving changes always asks for the admin password</b>, so your child can look but not touch.</p>
<img class="shot" alt="PlayCap control panel" src="data:image/png;base64,${IMG_EN}">
<ul>
<li><b>+30 min today</b>: one-off extension, resets tomorrow.</li>
<li><b>Monitored apps</b>: add e.g. <code>roblox,minecraft</code> to limit more games.</li>
<li>Terminal fans: <code>playcap status</code> / <code>sudo playcap --help</code></li>
</ul>
<div class="tip">PlayCap counts only actual play. Roblox quietly stays resident after you close its window - that idle time never burns the budget.</div>
<h2>5. Uninstall</h2>
<p>Double-click <b>Uninstall.command</b> in this folder.</p>
<h2>Support</h2>
<p>Questions or trouble: reply to your purchase receipt email, or open an issue at the project page linked from your receipt. Please include the output of <code>playcap status</code>.</p>
</body></html>
EOF

cat > "$OUT/セットアップガイド（日本語）.html" <<EOF
<!DOCTYPE html><html lang="ja"><head><meta charset="utf-8">
<title>PlayCap セットアップガイド</title><style>${CSS}</style></head><body>
<h1>PlayCap セットアップガイド</h1>
<p>所要時間は約10分。お子さんの Mac に<b>親の管理者アカウント</b>でログインして作業してください。</p>
<h2>1. 事前確認</h2>
<ol>
<li>お子さんのアカウントが「<b>標準ユーザー</b>」であること。確認: システム設定 &gt; ユーザとグループ。「管理者」なら「このユーザにこのコンピュータの管理を許可」をオフに（データは消えません）。</li>
<li>インストーラも自動チェックし、管理者のままなら中断して知らせます。</li>
</ol>
<h2>2. インストール</h2>
<ol>
<li>展開した <b>PlayCap</b> フォルダごと、お子さんの Mac へコピー（AirDrop・USB・共有フォルダ）。</li>
<li><b>Install.command</b> をダブルクリック。<div class="warn">「開発元を確認できないため開けません」と出たら: ファイルを右クリック &gt; <b>開く</b> &gt; もう一度<b>開く</b>。Apple の公証を未取得のため初回のみ出ます。</div></li>
<li>管理者パスワードを入力。</li>
<li>ユーザー一覧が出たらお子さんのアカウント名を入力。</li>
<li>「Install complete / インストール完了」と設定が表示されれば成功です。</li>
</ol>
<p>初期設定: <b>平日120分 / 休日180分 / 利用できる時間帯 07:00〜21:00</b></p>
<h2>3. 動作テスト（初回のみ・5分）</h2>
<ol>
<li>アプリケーションフォルダの <b>PlayCap</b> を開き、一時的に上限を2分に設定（管理者パスワードが必要）。</li>
<li>お子さんのアカウントで Roblox を起動 → <b>約2分で自動終了すれば成功</b>。通知の許可を求められたら「許可」。</li>
<li>親アカウントに戻り、本来の設定に戻す。</li>
</ol>
<h2>4. ふだんの使い方</h2>
<p>親用の設定画面です（アプリケーション &gt; PlayCap）。閲覧は誰でもできますが、<b>保存には必ず管理者パスワードが必要</b>なので、お子さんは見るだけで変更できません。</p>
<img class="shot" alt="PlayCap 設定画面" src="data:image/png;base64,${IMG_JA}">
<ul>
<li><b>今日だけ +30分</b>: その日限りの延長。翌日自動で元通り。</li>
<li><b>監視するアプリ</b>: <code>roblox,minecraft</code> のように追加すると他のゲームも制限できます。</li>
<li>ターミナル派: <code>playcap status</code> / <code>sudo playcap --help</code></li>
</ul>
<div class="tip">PlayCap がカウントするのは「実際に遊んでいる時間」だけ。最近の Roblox はウィンドウを閉じても裏で常駐しますが、その待機時間で持ち時間は減りません。</div>
<h2>5. アンインストール</h2>
<p>同じフォルダの <b>Uninstall.command</b> をダブルクリック。</p>
<h2>サポート</h2>
<p>不明点・不具合は購入レシートのメールに返信してください（レシート記載のプロジェクトページからも連絡できます）。<code>playcap status</code> の表示を添えていただけると解決が早くなります。</p>
</body></html>
EOF
echo "generated: $OUT"
