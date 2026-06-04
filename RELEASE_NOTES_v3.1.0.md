# Release Notes — kazahana for iOS v3.1.0

## EN

### New Features

- **Bluesky verification badges** — kazahana for iOS now displays the verification badges introduced by Bluesky. Verified accounts show a blue checkmark seal and trusted verifiers show a shield icon, displayed next to display names on post cards, profile headers, user lists (followers/following/search results), and notifications. Uses native SF Symbols for a consistent iOS look and feel.
- **Verified / unverified notification reasons** — The new `verified` and `unverified` notification types are fully supported with dedicated icons (checkmark seal / xmark seal), colored labels (sky blue / orange), and proper non-navigable tap handling. All notification reason labels are now localized across 11 languages.

### Bug Fixes

- **BSAF unregistered bot parsing** — The severity color border, BSAF tag badges, and duplicate detection were previously applied to all `bsaf:v1`-tagged posts regardless of whether the posting bot was registered by the user. This could incorrectly style posts from unregistered bots and hide registered bot posts via duplicate grouping. BSAF parsing and duplicate detection are now restricted to posts from registered bots only, matching the existing filter behavior.

### Documentation

- `README.md` / `README.ja.md` updated with verification badge and notification features

---

## JA

### 新機能

- **Bluesky 認証バッジ表示** — Bluesky の認証システムに対応しました。認証済みアカウントには青いチェックマーク、信頼できる認証機関にはシールドアイコンを表示名横に表示します。投稿カード、プロフィールヘッダー、ユーザーリスト（フォロワー/フォロー中/検索結果）、通知画面の全箇所に展開しています。iOS ネイティブの SF Symbols を使用し、OS に馴染むデザインです。
- **認証通知（verified / unverified）対応** — 新しい通知理由 `verified`（認証付与）と `unverified`（認証解除）に対応しました。専用アイコン（チェックマーク / バツマーク）、色分けラベル（スカイブルー / オレンジ）、非遷移タップ処理を実装しています。全通知理由ラベルを11言語にローカライズしました。

### バグ修正

- **BSAF 未登録 Bot のパースバグ修正** — `bsaf:v1` タグ付き投稿に対し、ユーザーが登録していない Bot からの投稿にも深刻度カラーボーダー・BSAF タグバッジ・重複検出が適用されていました。これにより未登録 Bot の投稿が意図せずスタイリングされたり、重複グループ化により登録 Bot の投稿が非表示になる問題がありました。BSAF パースと重複検出を登録済み Bot の投稿のみに限定し、既存のフィルタ動作と整合させました。

### ドキュメント

- `README.md` / `README.ja.md` — 認証バッジ表示・認証通知機能を追記
