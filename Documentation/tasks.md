# kazahana-ios 開発タスク・進捗記録

最終更新: 2026-03-18

---

## 進捗サマリー

- Phase 1 (基盤構築): 5/5 ✅ 完了
- Phase 2 (コア機能): 8/8 ✅ 完了
- Phase 3 (通知・プロフィール・検索): 6/6 ✅ 完了
- Phase 3.5 (UX改善・バグ修正): 12/12 ✅ 完了
- Phase 4 (DM・モデレーション・設定): 0/6
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

- [ ] ダイレクトメッセージ（ConversationListView, MessageThreadView, ChatViewModel）
- [ ] コンテンツモデレーション（ModerationService, ContentWarningView）
- [ ] 通報機能
- [ ] テーマ切り替え（ライト/ダーク/システム）
- [ ] 多言語対応（Localizable.xcstrings, 11言語）
- [ ] 設定画面（SettingsView, SettingsViewModel）

---

## Phase 5: BSAF・高度な機能 — 未着手

- [ ] BSAF対応（BSAFService, BSAFSettingsView）
- [ ] スレッドゲート / ポストゲート
- [ ] 共有シート連携（Share Extension）
- [ ] ディープリンク（Universal Links）

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

- [ ] **画像添付**: ComposeView のフォトライブラリ選択・uploadBlob は未実装（Phase 2.5）
- [ ] **メンション DID 解決**: RichTextParser.detectFacets でメンションを検出するが、resolveHandle による DID 解決は未実装。投稿時メンションのリンクが効かない
- [ ] **ブックマーク**: AT Protocol にネイティブブックマーク API がないため設計要検討
- [ ] **画像読み込み**: 現在 `AsyncImage` を使用。Kingfisher or Nuke の導入を Phase 4 以降で検討
- [ ] **バックグラウンドポーリング**: BGAppRefreshTask 未実装（Phase 4以降）
- [ ] **Unit Tests**: テストは空のまま。Phase 4 以降でモデル・サービス層を追加予定
- [ ] **Bundle ID**: 現在 Xcode デフォルト。`com.kazahana.app` への変更が必要（App Store 配布前）
- [ ] **検索デバウンス**: SearchViewModel は Task キャンセルで対応しているが、厳密なデバウンス実装は未対応
- [ ] **引用数タップ**: ThreadView の引用数は PostActorListView 非対応（app.bsky.feed.getQuotes API は未実装）

---

## ファイル構成（2026-03-18 Phase 3.5 完了時点）

```
kazahana-ios/
├── kazahana_iosApp.swift
├── ContentView.swift              # ルートビュー + MainTabView（Phase 3 タブ更新済み）
├── Models/
│   ├── Session.swift
│   ├── Post.swift                 # PostRecordCreate(embed対応), QuoteEmbedRecord, FeedViewPost(Hashable) 等
│   ├── Profile.swift
│   └── Notification.swift        # AppNotification, isViaRepost, reasonLabel/Icon/Color
├── Services/
│   ├── ATProtoClient.swift        # XRPC クライアント + getRecord
│   ├── AuthService.swift
│   ├── SessionStore.swift
│   ├── TimelineService.swift
│   ├── PostService.swift          # createPost(quotePost対応) / getLikes / getRepostedBy
│   ├── RichTextParser.swift       # Facet 解析・AttributedString 変換・自動検出
│   ├── NotificationService.swift  # listNotifications / getUnreadCount / updateSeen
│   ├── GraphService.swift         # follow / unfollow / getFollowers / getFollows
│   ├── SearchService.swift        # searchActors / searchPosts
│   └── FeedService.swift          # getSavedFeeds / getFeed / getTimeline + FeedSource enum
├── ViewModels/
│   ├── AuthViewModel.swift
│   ├── TimelineViewModel.swift    # FeedSource 対応（following / custom feed）
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
│   │   └── PostCardView.swift     # onTapReply / onTapLikeCount / onTapRepostCount / onTapQuote
│   ├── Compose/
│   │   └── ComposeView.swift      # 返信・引用投稿プレビュー対応
│   ├── Thread/
│   │   └── ThreadView.swift       # 統計行タップ→ユーザーリスト・引用投稿ボタン
│   ├── Notification/
│   │   ├── NotificationListView.swift
│   │   └── NotificationItemView.swift
│   ├── Profile/
│   │   ├── ProfileView.swift      # ProfileScreenView + ProfileHeaderView（isSelf対応）
│   │   └── UserListView.swift     # フォロワー/フォロー中一覧 + フォロー/解除ボタン
│   ├── Search/
│   │   └── SearchView.swift       # SearchView + ActorRowView + SearchPostRowView（スレッド遷移）
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
