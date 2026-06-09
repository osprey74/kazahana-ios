[English](README.md)

# kazahana for iOS

**軽量な Bluesky iOS クライアント**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## 概要

kazahana for iOS は、Swift と SwiftUI で構築されたネイティブ Bluesky クライアントです。
[デスクトップ版](https://github.com/osprey74/kazahana)と同じ「軽量・高速・シンプル」な体験を iPhone / iPad で提供します。

## 設計思想

kazahana は全機能を網羅するスタンドアロンアプリではなく、**軽快に日常利用する閲覧・投稿特化クライアント**です。

- **日常操作は kazahana で** — タイムライン閲覧、投稿、通知確認、検索、DM など。
- **設定・管理は Bluesky ウェブ版で** — アカウント管理、ブロック/ミュート一覧管理などは [bsky.app](https://bsky.app/) で行う前提です。

## 機能

- **タイムライン** — ホームタイムライン、カスタムフィード切り替え、自動更新（間隔設定可）、プルリフレッシュ、無限スクロール
- **投稿表示** — リッチテキスト（メンション・リンク・ハッシュタグ）、画像（最大10枚・ギャラリーカルーセル対応）、動画（最大300 MB）、外部リンクカード、引用投稿
- **インタラクション** — いいね・リポスト・引用投稿・返信（楽観的 UI 更新）
- **スレッド画面** — 親投稿チェーン、フォーカス投稿（統計付き）、返信一覧、統計数値タップでユーザー一覧表示
- **通知** — like-via-repost / repost-via-repost / 認証通知を含む全通知タイプに対応
- **認証バッジ** — Bluesky 認証マーク・信頼できる認証機関バッジを表示名横に表示
- **プロフィール** — 投稿/返信/メディア/いいねタブ、ピン留め投稿、フォロー管理、フォロワー/フォロー中一覧、プロフィール内検索
- **検索** — アクター検索・投稿検索、検索履歴（個別削除・一括削除）
- **投稿作成** — 新規投稿・返信・引用投稿、画像最大10枚（クロップ・ALT テキスト・ギャラリー自動切替）・動画添付（300 MB・サーバー制限チェック対応）、アップロード進捗表示、メンション補完、スレッドゲート（返信制限）・ポストゲート（引用制限）、キャンセル時の下書き保存
- **ダイレクトメッセージ** — 会話一覧、メッセージスレッド、絵文字リアクション、ユーザー検索履歴付き新規会話作成
- **コンテンツモデレーション** — ラベル別フィルタ（hide/warn/ignore）、成人向けコンテンツ切り替え、投稿通報
- **設定** — テーマ、投稿言語、自動更新間隔、via 表示、Claude API キー（ALT テキスト自動生成）
- **共有・ディープリンク** — iOS 共有シートで投稿 URL をシェア、`kazahana://` カスタム URL スキームで他アプリから画面遷移
- **避難誘導補助** — 気象庁の危険度情報（bsaf-kikikuru-bot）に基づく最寄り避難所検索、コンパスによるオフラインナビ、BSAF 自動検知による警報バナー表示
- **バックグラウンド更新** — 定期バックグラウンドポーリングと未読通知のローカルプッシュ通知

## 技術スタック

| 技術 | 用途 |
|------|------|
| [Swift](https://www.swift.org/) | プログラミング言語 |
| [SwiftUI](https://developer.apple.com/xcode/swiftui/) | UIフレームワーク |
| [AT Protocol](https://atproto.com/) | Bluesky API |

## 動作要件

- iOS 17.0 以上
- Xcode 16.0 以上

## 開発

```bash
# リポジトリのクローン
git clone https://github.com/osprey74/kazahana-ios.git

# Xcode で開く
open kazahana-ios.xcodeproj
```

## 関連プロジェクト

- [kazahana](https://github.com/osprey74/kazahana) — デスクトップ版 (Windows / macOS)
- [kazahana-android](https://github.com/osprey74/kazahana-android) — Android版
- [BSAF Protocol](https://github.com/osprey74/bsaf-protocol) — Bluesky Structured Alert Feed 仕様

## ライセンス

[MIT License](LICENSE)

## Support / 開発を応援する

kazahana を気に入っていただけたら、開発の継続を応援してください ☕

[![GitHub Sponsors](https://img.shields.io/badge/Sponsor-GitHub-ea4aaa?logo=github)](https://github.com/sponsors/osprey74)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-ff5e5b?logo=ko-fi)](https://ko-fi.com/osprey74)
