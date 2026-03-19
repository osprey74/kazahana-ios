# kazahana-ios 開発タスク・進捗記録

最終更新: 2026-03-19

---

## 進捗サマリー

- Phase 1 (基盤構築): 5/5 ✅ 完了
- Phase 2 (コア機能): 8/8 ✅ 完了
- Phase 3 (通知・プロフィール・検索): 6/6 ✅ 完了
- Phase 3.5 (UX改善・バグ修正): 12/12 ✅ 完了
- Phase 4 (DM・モデレーション・設定): 3/7
- Phase 5 (BSAF・高度な機能): 0/4

---

## Phase 1: 基盤構築（MVP）— 完了 ✅

- [x] プロジェクトディレクトリ構造を仕様書通りに整備
- [x] AT Protocol HTTP クライアント (URLSession + async/await)
  - ATProtoClient: 認証ヘッダー自動付与・401自動リフレッシュ・429バックオフ
  - SessionStore: Keychain 永続化
  - AuthService: createSession / deleteSession / PDS 解決
  - TimelineService: getTimeline (cursor ページネーション)
- [x] 認証機能 (ログイン / セッション永続化 / トークンリフレッシュ / ログアウト)
  - AuthViewModel (@Observable), LoginView
- [x] ホームタイムライン表示 (getTimeline + 投稿カード)
  - TimelineViewModel, TimelineView, PostCardView
  - AvatarView, ImageGridView, LinkCardView, QuoteEmbedView
- [x] Pull-to-Refresh + 無限スクロール (cursor ベース)

---

## Phase 2: コア機能 — 完了 ✅

- [x] いいね / リポスト (createRecord / deleteRecord)
  - PostService: like / unlike / repost / unrepost
  - PostCardView: 楽観的 UI 更新（タップ即時反映、失敗時ロールバック）
- [x] 投稿作成画面（ComposeView, ComposeViewModel）
  - テキスト入力、文字数カウント（300 grapheme 単位・円形インジケーター）
  - リプライ対応（返信先プレビュー表示）
  - FAB から起動（TimelineView の右下ボタン）
- [x] リッチテキスト表示（RichTextParser: Facet → AttributedString）
  - メンション・URL・ハッシュタグを自動検出してリンク化
  - UTF-8 バイトオフセット ↔ String.Index 変換実装
- [x] リプライ（返信先投稿の表示、ReplyTarget による PostService.createPost 連携）
- [x] スレッド表示（ThreadView, ThreadViewModel, PostService.getThread）
  - 親投稿チェーン（再帰表示）・フォーカス投稿（大きく表示）・返信一覧
- [x] 画像フルスクリーン表示（ImageViewer: TabView ページング・ピンチズーム・ダブルタップズーム）
- [x] 動画再生（VideoPlayerView: AVPlayer + HLS、フルスクリーンシート）
- [x] スレッド遷移（PostCardView タップ → NavigationStack push → ThreadView）

---

## Phase 3: 通知・プロフィール・検索 — 完了 ✅

- [x] 通知一覧 + 未読バッジ
  - NotificationService: listNotifications / getUnreadCount / updateSeen
  - NotificationViewModel (@Observable, cursor ページネーション)
  - NotificationListView + NotificationItemView (reason アイコン・色・テキスト)
  - String+DateFormatting.swift: `relativeFormatted` 拡張（相対時刻表示）
- [x] プロフィール表示 + フォロー / フォロー解除
  - GraphService: follow / unfollow / getProfile / getAuthorFeed
  - ProfileViewModel (@Observable, フォロー楽観的 UI)
  - ProfileScreenView + ProfileHeaderView（バナー・アバター・統計・フォローボタン）
- [x] 検索（アクター検索 + ポスト検索）
  - SearchService: searchActors / searchPosts
  - SearchViewModel (@Observable, タブ切り替え, Task キャンセルによるデバウンス)
  - SearchView (Picker タブ・searchable・ActorRowView・SearchPostRowView)
- [x] カスタムフィード / フォロータイムライン切り替え
  - FeedService: getSavedFeeds / getFeed / getTimeline
  - FeedSource enum: .following / .custom(GeneratorView)
  - TimelineViewModel: FeedSource 対応に更新
  - FeedSelectorView: 保存済みフィード一覧シート
  - TimelineView: ナビバー左ボタン → FeedSelectorView シート表示
- [x] MainTabView 更新
  - 検索タブ → SearchView
  - 通知タブ → NotificationListView
  - プロフィールタブ → ProfileScreenView (self DID)
  - メッセージタブは Phase 4 プレースホルダーのまま

---

## Phase 3.5: UX改善・バグ修正 — 完了 ✅

- [x] 「リポストへのいいね / リポストをリポスト」通知の対応
  - `like-via-repost` / `repost-via-repost` reason を正しく処理
  - `com.atproto.repo.getRecord` で repost レコードを取得 → 元投稿 URI を解決
  - NotificationViewModel に `resolvedRepostURIs` キャッシュを追加
- [x] 画像2枚横幅はみ出しバグ修正
  - ImageGridView: `Color.clear.overlay { AsyncImage }.clipped()` パターンに変更
- [x] PostCardView 返信ボタン → ComposeView を直接開く（スレッド遷移ではなく）
  - `onTapReply: ((PostView) -> Void)?` コールバックを追加
- [x] ComposeView 真っ白バグ修正
  - `sheet(isPresented:) { if let }` → `sheet(item:) { item in }` に変更（ThreadView, NotificationListView）
- [x] 検索結果の投稿タップ → スレッド遷移
  - SearchView に `selectedPostURI: IdentifiableString?` state + navigationDestination 追加
- [x] プロフィール画面: 自分のプロフィールでフォローボタンを非表示
  - ProfileHeaderView に `isSelf: Bool` を追加
- [x] プロフィール画面: フォロワー数・フォロー数タップでユーザーリスト表示
  - UserListView 新規作成（`UserListType` enum: `.followers` / `.following`）
  - GraphService: `getFollowers` / `getFollows` 追加
- [x] UserListView: フォロー/フォロー解除ボタン追加
  - フォロワー一覧でフォロー状態を表示、タップでトグル
  - フォロー中一覧でフォロー解除ボタンを表示
  - `followOverrides` による楽観的 UI 更新
- [x] アクションボタンの数字タップでユーザーリスト表示（PostActorListView）
  - PostActorListView 新規作成（`PostActorListType` enum: `.likes` / `.reposts`）
  - PostService: `getLikes` / `getRepostedBy` 追加
  - PostCardView: いいね数・リポスト数の数字部分を独立したボタンに分離
  - TimelineView: `postActorListType` state + navigationDestination 追加
- [x] ThreadView: 統計行（リポスト数・いいね数）タップで PostActorListView を表示
  - ThreadView に `postActorListType: PostActorListType?` state + navigationDestination 追加
- [x] 引用投稿ボタンの追加
  - PostCardView・ThreadView に `quote.bubble` アイコンボタンを追加
  - ComposeView: `quotedPost: PostView?` パラメータ追加、引用プレビュー表示
  - PostRecordCreate に `embed: QuoteEmbedRecord?` フィールド追加
  - PostService.createPost に `quotePost: PostView?` パラメータ追加
- [x] フィード選択ボタンのアイコン変更（`list.bullet`）
  - TimelineView ナビバー左ボタンアイコンを `list.bullet` に変更

---

## Phase 4: DM・モデレーション・設定 — 未着手

### 4-A: 投稿アクション補完（優先度：高）
- [x] **投稿削除** — 自分の投稿の三点メニューから削除（PostCardView + ThreadView）
- [x] **投稿の三点メニュー** — 翻訳（Google翻訳を外部ブラウザで開く）、リンクコピー
  - PostCardView `authorRow` に三点メニュー（`ellipsis`）ボタンを追加
  - 自分の投稿の場合のみ「削除」を表示（`currentUserDID` 比較）
  - TimelineViewModel に `removePost(uri:)` を追加（削除後のローカル除去）
- [ ] **メンションオートコンプリート** — ComposeView で `@` 入力時に `searchActorsTypeahead` で候補表示

### 4-B: 画像・動画添付（優先度：高）
- [x] **画像添付** — ComposeView: PhotosPicker + `uploadBlob` + プレビュー表示（最大4枚）
  - `ATProtoClient.uploadBlob(data:mimeType:)` 追加
  - `PostService.uploadImage(data:mimeType:)` 追加
  - `PostEmbedCreate` enum: `.images` / `.record` / `.recordWithMedia` で embed を統一
  - `PostRecordCreate.embed` の型を `QuoteEmbedRecord?` → `PostEmbedCreate?` に変更
  - `ImageEmbedCreate`, `ImageEmbedItem`, `BlobRef`, `UploadBlobResponse` モデル追加
  - ComposeView: `PhotosPicker` ボタン、画像プレビュー行（削除・Alt入力対応）
- [x] **画像 Alt テキスト入力** — 各画像サムネイルタップで Alert ダイアログ入力
- [ ] **動画添付** — ComposeView: フォトライブラリ選択 + `uploadBlob`（最大100MB, MP4/MOV等）

### 4-C: コンテンツモデレーション（優先度：高）
- [ ] **ラベル判定** — `moderatePost` / `moderateProfile` 相当のロジック実装
- [ ] **投稿フィルタ** — `filter` 判定で投稿をタイムライン・検索から除外
- [ ] **投稿ブラー** — `blur` 判定でオーバーレイ表示、「表示する」ボタンで解除
- [ ] **メディアブラー** — 画像のみブラー（本文は表示）
- [ ] **ContentWarningView** — モデレーション警告UI共通コンポーネント
- [ ] **通報機能** — 投稿/ユーザーの通報（`com.atproto.moderation.createReport`、理由選択付き）

### 4-D: 設定画面（優先度：中）
- [x] **設定画面** — SettingsView + AppSettings（@Observable singleton、UserDefaults永続化）
  - `AppSettings.swift`: theme / showVia を UserDefaults で永続化
  - `SettingsView.swift`: Form UI（テーマ Picker・via Toggle・アカウント情報・バージョン）
  - プロフィール画面ツールバーに設定ボタン（`gearshape`）追加、ログアウトを設定画面内に移動
  - `kazahana_iosApp`: `preferredColorScheme` でテーマをウィンドウ全体に適用
- [x] **テーマ切り替え** — ライト / ダーク / システム連動
- [x] **投稿元表示（via）** — `PostRecordCreate` に `via: String?` フィールド追加
  - ComposeView で AppSettings.showVia に基づき "Kazahana for iOS" を渡す
- [ ] **モデレーション設定** — 成人向けコンテンツ表示 ON/OFF、ラベル別設定（hide/warn/ignore）
- [ ] **ポーリング間隔設定** — タイムライン自動更新の間隔（30〜120秒）

### 4-E: プロフィール機能補完（優先度：中）
- [ ] **プロフィール追加タブ** — 返信一覧 / いいね一覧 / メディア一覧
  - `getAuthorFeed(filter: posts_with_replies)` / `getActorLikes` / `getAuthorFeed(filter: posts_with_media)`
- [ ] **ピン留め投稿表示** — プロフィール先頭にピン留め投稿を表示
- [ ] **プロフィール内検索** — `searchPosts(author: actor, q: query)` でタブ内絞り込み

### 4-F: ダイレクトメッセージ（優先度：中）
- [ ] **会話一覧** — `chat.bsky.convo.listConvos`、未読バッジ
- [ ] **メッセージ送受信** — `chat.bsky.convo.getMessages` / `sendMessage`
- [ ] **メッセージ削除** — `chat.bsky.convo.deleteMessageForSelf`
- [ ] **新規会話作成** — `chat.bsky.convo.getConvoForMembers`（ユーザー検索から開始）
- [ ] **既読処理** — `chat.bsky.convo.updateRead`
- [ ] **会話ミュート/退出** — `muteConvo` / `leaveConvo`
- [ ] **メッセージリクエスト承認** — `acceptConvo`
- [ ] **自動更新** — 15秒ポーリング（メッセージ）、30秒ポーリング（未読数）

### 4-G: 多言語対応（優先度：低）
- [ ] **多言語対応** — Localizable.xcstrings（11言語: ja, en, pt, de, zh-TW, zh-CN, fr, ko, es, ru, id）
  - デスクトップ版 `src/i18n/locales/*.json` を `.xcstrings` 形式に変換して流用

---

## Phase 5: BSAF・高度な機能 — 未着手

### 5-A: BSAF対応（優先度：中）
- [ ] **BSAF マスタートグル** — 設定画面でオン/オフ
- [ ] **Bot 定義 JSON パーサー & バリデーター** — デスクトップ版 `bsaf.ts` のロジックを移植
- [ ] **Bot 登録** — URL 入力で Bot 定義を fetch・登録
- [ ] **Bot 登録解除** — 登録解除 + 自動アンフォロー
- [ ] **動的フィルタ UI** — Bot 定義に基づくフィルタ選択肢の自動生成
- [ ] **タイムライン BSAF フィルタリング** — AND 条件フィルタ
- [ ] **重複投稿検出 & 折りたたみ** — 同一イベントの折りたたみ
- [ ] **深刻度カラーボーダー表示** — BSAF 投稿の左ボーダー色
- [ ] **BSAF タグ表示** — 投稿本文下にタグバッジ表示
- [ ] **Bot Definition 自動更新チェック** — アプリ起動時に更新確認

### 5-B: 投稿作成補完（優先度：中）
- [ ] **スレッドゲート** — 返信制限設定（全員/メンション/フォロワー/フォロー中/不可）
- [ ] **ポストゲート** — 引用制限設定（引用を許可しない）
- [ ] **スレッド投稿** — 複数ポストを繋いで一括投稿

### 5-C: モバイル固有機能（優先度：低）
- [ ] **共有シート連携（受信）** — Share Extension: 他アプリからテキスト/URLを受け取り投稿作成画面を開く
- [ ] **共有シート連携（送信）** — `UIActivityViewController` で投稿URLを共有
- [ ] **ディープリンク** — Universal Links / カスタムURLスキーム（`kazahana://`）
- [ ] **バックグラウンドポーリング** — `BGAppRefreshTask` による通知・タイムライン更新

### 5-D: プロフィール追加機能（優先度：低）
- [ ] **スターターパック閲覧** — `app.bsky.graph.getStarterPack` / `getActorStarterPacks`
- [ ] **カスタムフィード一覧** — `app.bsky.feed.getActorFeeds`（プロフィールタブ）
- [ ] **リスト一覧** — `app.bsky.graph.getLists`（プロフィールタブ）
- [ ] **リストフィード閲覧** — `app.bsky.feed.getListFeed`

---

## 技術的決定事項・方針

### アーキテクチャ
- 状態管理: `@Observable` (Observation framework, iOS 17+)
- DI: `@Environment` 経由で ViewModel を伝播
- HTTP: `URLSession` + `async/await`（Combine 不使用）
- 永続化: Keychain（セッション情報）、SwiftData は将来のキャッシュ用に検討

### AT Protocol
- PDS解決: `/.well-known/atproto-did` → `plc.directory/{did}` の順で解決、フォールバックは `bsky.social`
- トークンリフレッシュ: 401 時に `ATProtoClient` が自動リトライ（1回のみ、無限ループ防止）
- レート制限: 429 時に `retry-after` ヘッダーを参照して指数バックオフ（最大3回）
- `refreshSession` は `refreshJwt` を Bearer トークンとして使用（`accessJwt` ではない）

### 命名規則・解決済み問題
- SwiftUI の `Label` と AT Protocol の `Label` 型名が衝突 → `ContentLabel` に改名
- `PostEmbed` enum の循環参照 → `indirect enum PostEmbed` + `PostRecordSimple` で解決
- `ThreadViewPost` の再帰的な struct → `final class` に変更
- `@ViewBuilder` の opaque return type が自己参照 → `AnyView` でラップして解決
- `FeedViewPost` を `Hashable` 対応（navigationDestination(item:) に必要）
- `PostView` を `Identifiable` 対応（ForEach での使用に必要）
- `ProfileView` (SwiftUI) と AT Protocol モデル `ProfileView` の衝突 → `ProfileScreenView` に改名
- `foregroundStyle(.white)` の HierarchicalShapeStyle コンテキストエラー → `Color.white` に変更
- `sheet(isPresented:) { if let }` による ComposeView 真っ白バグ → `sheet(item:)` に変更
- `StrongRef` の重複定義（Post.swift と PostService.swift）→ PostService.swift の定義を使用
- trailing closure 後のラベル付き引数構文エラー → 全引数を括弧内に記述する形式に変更

---

## 既知の課題・TODO

- [ ] **画像添付**: ComposeView のフォトライブラリ選択・uploadBlob は未実装 → Phase 4-B
- [ ] **メンション DID 解決**: RichTextParser.detectFacets でメンションを検出するが、resolveHandle による DID 解決は未実装。投稿時メンションのリンクが効かない → Phase 4-A（メンションオートコンプリートと同時実装予定）
- [ ] **ブックマーク**: AT Protocol にネイティブブックマーク API がないため設計要検討
- [ ] **画像読み込み**: 現在 `AsyncImage` を使用。Kingfisher or Nuke の導入を Phase 4 以降で検討
- [ ] **バックグラウンドポーリング**: BGAppRefreshTask 未実装 → Phase 5-C
- [ ] **Unit Tests**: テストは空のまま。Phase 4 以降でモデル・サービス層を追加予定
- [ ] **Bundle ID**: 現在 Xcode デフォルト。`com.kazahana.app` への変更が必要（App Store 配布前）
- [ ] **検索デバウンス**: SearchViewModel は Task キャンセルで対応しているが、厳密なデバウンス実装は未対応
- [ ] **引用数タップ**: ThreadView の引用数は PostActorListView 非対応（`app.bsky.feed.getQuotes` API は未実装）
- [ ] **コンテンツモデレーション**: タイムライン・検索・プロフィールでのラベル判定・ブラー・フィルタが未実装 → Phase 4-C
- [ ] **投稿削除**: 自分の投稿の三点メニューから削除する機能が未実装 → Phase 4-A
- [ ] **投稿元表示（via）**: 設定に基づきレコードにクライアント名を付与する機能が未実装 → Phase 4-D
- [ ] **DM（ダイレクトメッセージ）**: `chat.bsky.convo.*` API 全体が未実装 → Phase 4-F
- [ ] **プロフィール追加タブ**: 返信/いいね/メディア一覧が未実装 → Phase 4-E

---

## ファイル構成（2026-03-19 Phase 4-A/B/D 完了時点）

```
kazahana-ios/
├── kazahana_iosApp.swift          # AppSettings環境注入・preferredColorScheme適用
├── ContentView.swift              # ルートビュー + MainTabView（Phase 3 タブ更新済み）
├── Models/
│   ├── Session.swift
│   ├── Post.swift                 # PostEmbedCreate / ImageEmbedCreate / BlobRef / UploadBlobResponse 追加
│   ├── Profile.swift
│   └── Notification.swift        # AppNotification, isViaRepost, reasonLabel/Icon/Color
├── Services/
│   ├── ATProtoClient.swift        # XRPC クライアント + getRecord + uploadBlob
│   ├── AuthService.swift
│   ├── SessionStore.swift
│   ├── AppSettings.swift          # テーマ/via 設定（@Observable singleton）
│   ├── TimelineService.swift
│   ├── PostService.swift          # createPost(images対応) / uploadImage / getLikes / getRepostedBy
│   ├── RichTextParser.swift       # Facet 解析・AttributedString 変換・自動検出
│   ├── NotificationService.swift  # listNotifications / getUnreadCount / updateSeen
│   ├── GraphService.swift         # follow / unfollow / getFollowers / getFollows
│   ├── SearchService.swift        # searchActors / searchPosts
│   └── FeedService.swift          # getSavedFeeds / getFeed / getTimeline + FeedSource enum
├── ViewModels/
│   ├── AuthViewModel.swift
│   ├── TimelineViewModel.swift    # FeedSource対応 + removePost(uri:)
│   ├── ComposeViewModel.swift
│   ├── ThreadViewModel.swift
│   ├── NotificationViewModel.swift # resolvedRepostURIs キャッシュ
│   ├── ProfileViewModel.swift     # フォロー楽観的 UI 対応
│   └── SearchViewModel.swift      # タブ切り替え・Task キャンセルデバウンス
├── Views/
│   ├── Auth/
│   │   └── LoginView.swift
│   ├── Timeline/
│   │   ├── TimelineView.swift     # FAB・返信・引用・いいね/リポストユーザー一覧遷移
│   │   └── PostCardView.swift     # 三点メニュー(削除/翻訳/リンクコピー) + currentUserDID
│   ├── Compose/
│   │   └── ComposeView.swift      # 返信・引用投稿・画像添付（PhotosPicker+Alt入力）対応
│   ├── Thread/
│   │   └── ThreadView.swift       # 統計行タップ→ユーザーリスト・引用投稿ボタン
│   ├── Notification/
│   │   ├── NotificationListView.swift
│   │   └── NotificationItemView.swift
│   ├── Profile/
│   │   ├── ProfileView.swift      # ProfileScreenView + ProfileHeaderView（設定ボタン追加）
│   │   └── UserListView.swift     # フォロワー/フォロー中一覧 + フォロー/解除ボタン
│   ├── Search/
│   │   └── SearchView.swift       # SearchView + ActorRowView + SearchPostRowView（スレッド遷移）
│   ├── Settings/
│   │   └── SettingsView.swift     # テーマ切り替え・via表示・アカウント情報・ログアウト
│   └── Common/
│       ├── AvatarView.swift
│       ├── ImageGridView.swift    # Color.clear overlay パターン（画像はみ出し修正済み）
│       ├── ImageViewer.swift
│       ├── VideoPlayerView.swift
│       ├── LinkCardView.swift
│       ├── QuoteEmbedView.swift
│       ├── FeedSelectorView.swift  # フィード選択シート
│       └── PostActorListView.swift # いいね/リポストユーザー一覧
├── Extensions/
│   ├── IdentifiableString.swift
│   └── String+DateFormatting.swift # relativeFormatted（相対時刻表示）
└── Documentation/
    └── tasks.md
```
