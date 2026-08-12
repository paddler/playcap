# Roblox Limit

息子さんの MacBook Air（M5）で Roblox デスクトップアプリのプレイ時間を親が制限するシステム。
macOS スクリーンタイムが非 App Store 配布の Roblox を制御できない問題への自作対策。

**導入手順は [INSTALL.md](INSTALL.md) を参照。**

## 機能

- 1日の合計プレイ時間の上限（平日 / 休日で別設定）
- 利用できる時間帯の制限（例: 07:00〜21:00 以外は起動しても即終了）
- 残り10分・5分・1分で画面通知 → 上限で Roblox を自動終了
- 「今日だけ +30分」ボーナス延長（翌日自動リセット）
- 日別の使用履歴ログ
- 設定変更は管理者パスワード必須（子供は標準ユーザーのため回避不可）

## 構成

```
[root LaunchDaemon] 30秒ごとに monitor.sh を実行
      │
      ▼
[monitor.sh] ── pgrep でプロセス名 "roblox" を検知（-f 不使用: ブラウザ誤爆防止）
      │           ├─ 起動中なら使用時間を積算（日付変更でリセット）
      │           ├─ 残り時間に応じて通知（launchctl asuser + osascript）
      │           └─ 上限超過 / 時間帯外 → pkill
      ▼
[/Library/Application Support/RobloxLimit/]
      ├─ config     … 設定 (key=value, root所有・全員読取可)
      ├─ state      … 今日の使用秒数・ボーナス・警告段階
      └─ usage.log  … 日別履歴

[ctl.sh] 設定 CLI（/usr/local/bin/roblox-limit にリンク）。参照は誰でも、変更は root のみ
[Roblox Limit.app] 親用 GUI。変更時は管理者認証ダイアログ（= 親だけのゲート）
```

## リポジトリ構成

| パス | 内容 |
|---|---|
| `scripts/monitor.sh` | 監視デーモン本体（30秒ごとに1 tick 処理） |
| `scripts/ctl.sh` | 設定 CLI |
| `scripts/install.sh` / `uninstall.sh` | 息子機用インストーラ（対話式・標準ユーザー確認付き） |
| `daemon/*.plist` | LaunchDaemon 定義 |
| `gui/main.swift` | 親用 GUI（SwiftUI・swiftc のみでビルド可） |
| `gui/build.sh` | GUI ビルド（実行バイナリ名は LimitPanel ※） |
| `package.sh` | 配布 zip 作成 |

※ GUI のバイナリ名に "roblox" を含めると監視の pgrep に誤検知され GUI 自体が kill されるため、あえて `LimitPanel` にしている。

## 開発メモ

- ビルド: `./gui/build.sh`（CommandLineTools のみで可、Xcode 不要）
- 配布物作成: `./package.sh` → `dist/RobloxLimit-installer.zip`
- ロジックのテスト: 環境変数 `ROBLOX_LIMIT_DIR` でデータディレクトリを差し替えると root 不要で検証できる。偽 Roblox プロセスは**自前コンパイルした**バイナリを使うこと（`/bin/sleep` のコピーは Apple Silicon の AMFI に即 kill される）
- 設定ファイルは依存ゼロの key=value 形式（JSON パーサ不使用）

## 既知の限界

- アプリを別名コピーしてプロセス名を偽装すれば理論上回避可能（usage.log が数日ゼロなら疑うこと）
- 通知はベストエフォート（初回に macOS の通知許可が必要な場合あり）。kill 自体は通知と無関係に実行される
