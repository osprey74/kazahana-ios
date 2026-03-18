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

- **タイムライン** — ホームタイムライン、カスタムフィード切り替え、プルリフレッシュ、無限スクロール
- **投稿表示** — リッチテキスト（メンション・リンク・ハッシュタグ）、画像、動画、外部リンクカード、引用投稿
- **インタラクション** — いいね・リポスト・引用投稿・返信（楽観的 UI 更新）
- **スレッド画面** — 親投稿チェーン、フォーカス投稿（統計付き）、返信一覧、統計数値タップでユーザー一覧表示
- **通知** — like-via-repost / repost-via-repost を含む全通知タイプに対応
- **プロフィール** — 投稿一覧、フォロー/フォロー解除、フォロワー/フォロー中一覧（フォロー管理付き）
- **検索** — アクター検索・投稿検索、投稿タップでスレッド遷移
- **投稿作成** — 新規投稿・返信・引用投稿、文字数カウンター

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
