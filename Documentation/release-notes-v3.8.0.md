# kazahana for iOS v3.8.0

## 日本語

### ✨ 新機能・改善

- **動画 ALT テキスト表示** — サムネイル左下に ALT バッジ、動画下に ALT テキスト本文を表示。タイムライン／スレッド／通知／引用投稿内のすべての表示面に対応しました。
- **動画 ALT 入力 UI** — 投稿作成画面の動画プレビューに ALT ボタンと編集シートを追加。動画にも代替テキストを付けられるようになりました。
- **引用投稿内のメディア表示** — 引用投稿の中の画像・動画・外部リンクカードを表示するようになりました。
- **OP スレッド番号付けバッジ** — 連続スレッド内での位置を「2/3」形式のバッジで著者行に表示します（Bluesky 公式互換）。

### 🐛 不具合修正

- **メンション通知の修正** — プロフィール画面からの自動メンション挿入時に DID を正しく解決し、相手に通知が届くよう正しいファセットを生成するようにしました。

### 🔧 その他

- Mac Catalyst のシステムトレイ／ドラッグ&ドロップ対応の実現性を調査しました。

---

## English

### ✨ Features & Improvements

- **Video ALT text display** — Shows an ALT badge at the bottom-left of the thumbnail and the ALT text below the video, across the timeline, threads, notifications, and quote posts.
- **Video ALT input UI** — Added an ALT button and editor sheet to the video preview in the compose screen, so you can add alt text to videos.
- **Media in quote posts** — Images, videos, and external link cards inside quote posts are now rendered.
- **OP thread numbering badge** — Displays your position within a same-author thread as a "2/3" badge on the author row (compatible with the official Bluesky client).

### 🐛 Bug Fixes

- **Mention notifications fixed** — Auto-inserted mentions from a profile now resolve the DID and generate the correct facet, so the mentioned user receives the notification.

### 🔧 Other

- Investigated the feasibility of macOS Catalyst system tray / drag-and-drop support.

---

**Full Changelog**: https://github.com/osprey74/kazahana-ios/releases/tag/v3.8.0
