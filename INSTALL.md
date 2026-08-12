# Roblox Limit 導入手順（息子さんの MacBook で行う作業）

所要時間: 約10分。**親の管理者アカウント**でログインして作業してください。

## 1. 事前確認

- 息子さんのアカウントが「標準ユーザー」であること
  （システム設定 > ユーザとグループ で確認。「管理者」なら「このユーザにこのコンピュータの管理を許可」のチェックを外す）
- ※ install.sh も自動でチェックし、管理者のままなら中断して知らせます

## 2. インストール

1. `RobloxLimit-installer.zip` を AirDrop 等でこの Mac に送り、ダブルクリックで展開
2. ターミナルを開く（Launchpad > その他 > ターミナル）
3. 次を実行（`RobloxLimit` フォルダがダウンロードフォルダにある場合の例）:

```bash
cd ~/Downloads/RobloxLimit
```

```bash
sudo ./install.sh
```

4. 管理者パスワードを入力 → ユーザー一覧が出るので**息子さんのアカウント名**を入力
5. 「インストール完了」と現在の設定が表示されれば成功

デフォルト設定: **平日120分 / 休日180分 / 利用できる時間帯 07:00〜21:00**

## 3. 動作テスト（初回のみ・5分でできる）

1. 一時的に上限を極端に短くする:

```bash
sudo roblox-limit set-weekday 2 && sudo roblox-limit set-weekend 2
```

2. 息子さんのアカウントに切り替えて Roblox を起動 → **約2分でRobloxが自動終了すれば成功**
   （最初の警告通知が出たとき、macOS が通知の許可を求めてきたら「許可」を選ぶ）
3. Roblox 起動中に、実際のプロセス名も確認しておく:

```bash
ps aux | grep -i roblox | grep -v grep
```

   名前に「roblox」を含むプロセスが見えていれば OK（通常は RobloxPlayer）
4. 親アカウントに戻り、本番設定へ:

```bash
sudo roblox-limit set-weekday 120 && sudo roblox-limit set-weekend 180 && sudo roblox-limit reset-today
```

## 4. ふだんの使い方

- **設定変更**: アプリケーションフォルダの「Roblox Limit」を開く → 変更して保存（管理者パスワードが必要。息子さんは開いても閲覧のみ）
- **今日だけ延長**: GUI の「今日だけ +30分」ボタン（翌日自動で元に戻る）
- **ターミナル派の場合**:

```bash
roblox-limit status
```

```bash
sudo roblox-limit --help
```

- **使用履歴**: `/Library/Application Support/RobloxLimit/usage.log` に日別の使用分数が残ります

## 5. アンインストール

```bash
sudo ./uninstall.sh
```

## 仕組みと注意

- root 権限の監視プログラムが30秒ごとに Roblox の起動をチェックし、使用時間を積算。残り10分・5分・1分で通知し、上限か時間帯外になると Roblox を終了させます
- 息子さんは標準ユーザーのため、監視の停止・設定変更・時計変更はできません
- Mac がスリープ中はカウントされません（実プレイ時間のみ積算）
