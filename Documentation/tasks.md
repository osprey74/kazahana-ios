# kazahana-ios 開発タスク・進捗記録

最終更新: 2026-03-19 (DM 実装完了)

---

## 進捗サマリー

- Phase 1 (基盤構築): 5/5 ✅ 完了
- Phase 2 (コア機能): 8/8 ✅ 完了
- Phase 3 (通知・プロフィール・検索): 6/6 ✅ 完了
- Phase 3.5 (UX改善・バグ修正): 12/12 ✅ 完了
- Phase 4 (DM・モデレーション・設定): 27/28
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
- [x] **メンションオートコンプリート** — ComposeView で `@` 入力時に `searchActorsTypeahead` で候補表示、DID 解決も同時対応

### 4-B: 画像・動画添付（優先度：高）
- [x] **画像添付** — ComposeView: PhotosPicker + `uploadBlob` + プレビュー表示（最大4枚）
  - `ATProtoClient.uploadBlob(data:mimeType:)` 追加
  - `PostService.uploadImage(data:mimeType:)` 追加
  - `PostEmbedCreate` enum: `.images` / `.record` / `.recordWithMedia` で embed を統一
  - `PostRecordCreate.embed` の型を `QuoteEmbedRecord?` → `PostEmbedCreate?` に変更
  - `ImageEmbedCreate`, `ImageEmbedItem`, `BlobRef`, `UploadBlobResponse` モデル追加
  - ComposeView: `PhotosPicker` ボタン、画像プレビュー行（削除・Alt入力対応）
- [x] **画像 Alt テキスト入力** — 各画像サムネイルタップで Alert ダイアログ入力
- [x] **画像クロップ** — ComposeView: サムネイル右下の crop ボタンから `ImageCropView`（フルスクリーン）を開いてクロップ
  - `ImageCropView.swift` 新規作成（`Views/Compose/`）
  - 3モード: オリジナル比率維持 / 正方形 / 自由変形
  - 4隅 L 字ハンドル + 矩形内ドラッグで移動、三分割グリッド表示
  - `CGImage.cropping(to:)` で即時適用、ALT テキストは保持
  - `SelectedImage.image` を `var` に変更（クロップ後の置き換えを可能に）
- [x] **動画添付** — ComposeView: フォトライブラリ選択 + `app.bsky.video.uploadVideo`（MP4/MOV）
  - `Post.swift`: `VideoEmbedCreate` struct 追加（`app.bsky.embed.video` 書き込み用）
  - `PostEmbedCreate` enum に `.video(VideoEmbedCreate)` ケース追加
  - `PostService`: `uploadVideo(data:mimeType:)` + `createPost` に `video:` パラメータ追加
  - `ComposeView`: `SelectedVideo` struct / `PhotosPicker(.videos)` ボタン / サムネイルプレビュー / AVAssetImageGenerator でサムネイル生成 / アスペクト比自動取得
  - 画像と動画は排他（画像選択中は動画ボタン無効、動画選択中は画像ボタン無効）
  - `AVAssetExportSession` を廃止 → `loadTransferable(Data)` の生データを直接アップロード（バックグラウンド遷移による中断問題を解消）
  - `ATProtoClient`: `getServiceAuth` / `uploadVideoToService` / `getVideoJobStatus` 追加
  - `PostService.uploadVideo`: `video.bsky.app` 経由アップロード → ジョブポーリング → `BlobRef` 返却（サーバー側トランスコード）
  - `Post.swift`: `VideoUploadJobStatus` / `VideoJobStatusWrapper` struct 追加
  - MIME タイプ自動判定（`com.apple.quicktime-movie` → `video/quicktime`、それ以外 → `video/mp4`）
  - `PostRecord` / `PostRecordCreate` の `$via` CodingKey 修正（`via` → `"$via"`）

### 4-C: コンテンツモデレーション（優先度：高）— 完了 ✅
- [x] **ラベル判定** — `ModerationService.moderatePost` 実装（none/inform/mediaBlur/blur/filter の5段階判定）
- [x] **投稿フィルタ** — `filter` 判定で投稿をタイムライン・検索から除外（TimelineViewModel / SearchViewModel）
- [x] **投稿ブラー** — `blur` 判定で `PostBlurOverlay` 表示、「表示する」ボタンで一時解除
- [x] **メディアブラー** — 画像のみ `MediaBlurOverlay`（本文は表示）、「表示する」で一時解除
- [x] **ContentWarningView** — `PostBlurOverlay` / `MediaBlurOverlay`（`.ultraThinMaterial` 使用）
- [x] **通報機能** — `PostService.reportPost` / `reportAccount`（`com.atproto.moderation.createReport`）、`ReportView`（理由選択 + コメント + 送信）、PostCardView / ThreadView 三点メニューに統合

### 4-D: 設定画面（優先度：中）
- [x] **設定画面** — SettingsView + AppSettings（@Observable singleton、UserDefaults永続化）
  - `AppSettings.swift`: theme / showVia を UserDefaults で永続化
  - `SettingsView.swift`: Form UI（テーマ Picker・via Toggle・アカウント情報・バージョン）
  - プロフィール画面ツールバーに設定ボタン（`gearshape`）追加、ログアウトを設定画面内に移動
  - `kazahana_iosApp`: `preferredColorScheme` でテーマをウィンドウ全体に適用
- [x] **テーマ切り替え** — ライト / ダーク / システム連動
- [x] **投稿元表示（via）** — `PostRecordCreate` に `via: String?` フィールド追加
  - ComposeView で AppSettings.showVia に基づき "Kazahana for iOS" を渡す
- [x] **モデレーション設定** — 成人向けコンテンツ表示 ON/OFF、ラベル別設定（hide/warn/ignore）
- [x] **Claude API キー登録解除** — 登録済みキーがある場合のみ「APIキーを削除」ボタン表示、確認アラート付き
- [x] **検索履歴** — 検索履歴の永続化（UserDefaults・最大20件）、個別削除・一括削除
  - `SearchViewModel`: `searchHistory` / `addToHistory` / `deleteHistory(at:)` / `clearAllHistory()`
  - `SearchView`: クエリ空時に履歴一覧表示（タップで再検索・スワイプ削除・一括削除ボタン）
- [ ] **ポーリング間隔設定** — タイムライン自動更新の間隔（30〜120秒）

### 4-E: プロフィール機能補完（優先度：中）
- [x] **プロフィール追加タブ** — 返信一覧 / いいね一覧 / メディア一覧
  - `getAuthorFeed(filter: posts_with_replies)` / `getActorLikes` / `getAuthorFeed(filter: posts_with_media)`
  - `ProfileTab` enum (.posts/.replies/.media/.likes) + タブ別フィードキャッシュ
  - LazyVStack pinnedViews でプロフィールヘッダー＋タブバーを固定表示
- [x] **プロフィール画面 UX 改善** — ナビバー除去・設定ボタン配置変更・コンパクトヘッダー
  - `.toolbar(.hidden, for: .navigationBar)` でナビバー全体非表示
  - 設定ボタンをバナー右上にオーバーレイ（半透明黒円形）
  - スクロールアップ時にコンパクトヘッダー（アバター小＋名前＋設定ボタン）＋タブバーを固定表示
  - `onScrollGeometryChange(for:of:action:)` (iOS 17+) で `contentOffset.y` を直接監視
    - `GeometryReader` + `DispatchQueue.main.async` 方式を廃止（タブ切替・画面遷移での誤検知を解消）
    - タブ切替後も ScrollView の実際の offset を正確に反映、`ignoreNextGeometryUpdate` フラグ不要
- [x] **ピン留め投稿表示** — プロフィール先頭にピン留め投稿を表示
  - `Profile.swift`: `ProfileView` に `pinnedPost: PinnedPost?` フィールド追加
  - `ProfileViewModel`: `loadPinnedPost(postService:)` で `getPosts(uris:)` を呼び出して取得
  - `ProfileView`: フィード先頭に📌バッジ付き PostCardView を表示
- [x] **プロフィール内検索** — `searchPosts(author: actor, q: query)` でタブ内絞り込み
  - `SearchService`: `searchPostsByAuthor(query:author:limit:cursor:)` 追加（`author` パラメータ）
  - `ProfileViewModel`: `searchInProfile(query:)` / `loadMoreSearchResults()`（Task キャンセル対応）
  - `ProfileView`: 検索バー（×クリアボタン付き）→ クエリあり時は検索結果リスト（無限スクロール）

### 4-F: ダイレクトメッセージ（優先度：中）— 完了 ✅
- [x] **会話一覧** — `chat.bsky.convo.listConvos`、未読バッジ（タブアイコンに表示）
  - `ConversationListView.swift` / `ConversationRowView`（アバター・名前・プレビュー・未読バッジ・ミュート表示）
  - スワイプアクション: ミュート/ミュート解除・退出
- [x] **メッセージ送受信** — `chat.bsky.convo.getMessages` / `sendMessage`
  - `ChatThreadView.swift` / `MessageBubbleView`（自分=右青/相手=左グレー）
  - 送信ボックス（テキスト・送信ボタン）
- [x] **メッセージ削除** — `chat.bsky.convo.deleteMessageForSelf`（コンテキストメニューから削除）
- [x] **新規会話作成** — `chat.bsky.convo.getConvoForMembers`（ユーザー検索から開始）
  - `NewConversationView.swift`: `searchActorsTypeahead` → `getConvoForMembers` → スレッドへ遷移
- [x] **既読処理** — `chat.bsky.convo.updateRead`（メッセージ一覧表示時に自動既読）
- [x] **会話ミュート/退出** — `muteConvo` / `unmuteConvo` / `leaveConvo`
- [x] **メッセージリクエスト承認** — `acceptConvo`（ChatService に実装）
- [x] **自動更新** — 15秒ポーリング（メッセージ）、30秒ポーリング（未読数・会話一覧）
- 実装ファイル:
  - `ATProtoClient.swift`: `getWithProxy` / `postWithProxy` / `getWithProxyArrayParams` 追加
  - `Models/Conversation.swift`: ConvoView / ChatMember / ChatMessageView / ChatMessageViewOrDeleted など
  - `Services/ChatService.swift`: chat.bsky.convo.* 全API ラッパー
  - `ViewModels/ConversationListViewModel.swift` / `ViewModels/ChatThreadViewModel.swift`
  - `Views/Messages/ConversationListView.swift` / `ChatThreadView.swift` / `NewConversationView.swift`

### 4-G: 多言語対応（優先度：低）
- [x] **投稿言語設定** — 設定画面から投稿に付与する言語（`langs` フィールド）を選択
  - `AppSettings.PostLanguage` enum（system + 11言語）、`resolvedPostLangs` 計算プロパティ
  - 優先順: ユーザー設定 → Bluesky アカウントプリファレンス → 端末ロケール
  - ALT テキスト自動生成にも同じ言語設定を使用
- [x] **アプリ表示言語の多言語化** — Localizable.xcstrings（11言語: ja, en, pt, de, zh-TW, zh-CN, fr, ko, es, ru, id）
  - デスクトップ版 `src/i18n/locales/*.json` を `.xcstrings` 形式に変換して流用
  - 設定画面の「言語」Picker をアプリ表示言語の切り替えにも連動（`UserDefaults["AppleLanguages"]` + 再起動方式）

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

- [x] **画像添付**: ComposeView のフォトライブラリ選択・uploadBlob は未実装 → Phase 4-B（実装済み）
- [x] **メンション DID 解決**: RichTextParser.detectFacets でメンションを検出するが、resolveHandle による DID 解決は未実装 → Phase 4-A メンションオートコンプリートで対応（実装済み）
- [ ] **ブックマーク**: AT Protocol にネイティブブックマーク API がないため設計要検討
- [ ] **画像読み込み**: 現在 `AsyncImage` を使用。Kingfisher or Nuke の導入を Phase 4 以降で検討
- [ ] **バックグラウンドポーリング**: BGAppRefreshTask 未実装 → Phase 5-C
- [ ] **Unit Tests**: テストは空のまま。Phase 4 以降でモデル・サービス層を追加予定
- [ ] **Bundle ID**: 現在 Xcode デフォルト。`com.kazahana.app` への変更が必要（App Store 配布前）
- [ ] **検索デバウンス**: SearchViewModel は Task キャンセルで対応しているが、厳密なデバウンス実装は未対応
- [ ] **引用数タップ**: ThreadView の引用数は PostActorListView 非対応（`app.bsky.feed.getQuotes` API は未実装）
- [x] **コンテンツモデレーション**: タイムライン・検索・プロフィールでのラベル判定・ブラー・フィルタが未実装 → Phase 4-C（実装済み）
- [x] **投稿削除**: 自分の投稿の三点メニューから削除する機能が未実装 → Phase 4-A（実装済み）
- [x] **投稿元表示（via）**: 設定に基づきレコードにクライアント名を付与する機能が未実装 → Phase 4-D（実装済み）
- [ ] **DM（ダイレクトメッセージ）**: `chat.bsky.convo.*` API 全体が未実装 → Phase 4-F
- [x] **プロフィール追加タブ**: 返信/いいね/メディア一覧が未実装 → Phase 4-E（実装済み）

---

## ファイル構成（2026-03-19 Phase 4-G 多言語対応・画像クロップ完了時点）

```
kazahana-ios/
├── kazahana_iosApp.swift          # AppSettings環境注入・preferredColorScheme適用
├── ContentView.swift              # ルートビュー + MainTabView（Phase 3 タブ更新済み）
├── Localizable.xcstrings          # 11言語対応 String Catalog（ja/en/pt/de/zh-TW/zh-CN/fr/ko/es/ru/id）[NEW]
├── Models/
│   ├── Session.swift
│   ├── Post.swift                 # PostEmbedCreate / ImageEmbedCreate / BlobRef / UploadBlobResponse 追加
│   ├── Profile.swift              # PinnedPost struct 追加
│   └── Notification.swift        # AppNotification, isViaRepost, reasonLabel/Icon/Color
├── Services/
│   ├── ATProtoClient.swift        # XRPC クライアント + getRecord + uploadBlob
│   ├── AuthService.swift
│   ├── SessionStore.swift
│   ├── AppSettings.swift          # テーマ/via/言語/モデレーション設定（@Observable singleton）
│   ├── ModerationService.swift    # ラベル判定（none/inform/mediaBlur/blur/filter）
│   ├── TimelineService.swift
│   ├── PostService.swift          # createPost / uploadImage / getLikes / getRepostedBy / reportPost / reportAccount
│   ├── RichTextParser.swift       # Facet 解析・AttributedString 変換・自動検出
│   ├── NotificationService.swift  # listNotifications / getUnreadCount / updateSeen
│   ├── GraphService.swift         # follow / unfollow / getFollowers / getFollows / getAuthorFeed(filter) / getActorLikes
│   ├── SearchService.swift        # searchActors / searchPosts / searchPostsByAuthor
│   ├── FeedService.swift          # getSavedFeeds / getFeed / getTimeline + FeedSource enum
│   └── ClaudeService.swift        # ALT テキスト自動生成（Claude API）
├── ViewModels/
│   ├── AuthViewModel.swift
│   ├── TimelineViewModel.swift    # FeedSource対応 + removePost(uri:) + filterModeratedPosts
│   ├── ComposeViewModel.swift
│   ├── ThreadViewModel.swift
│   ├── NotificationViewModel.swift # resolvedRepostURIs キャッシュ
│   ├── ProfileViewModel.swift     # フォロー楽観的 UI + ProfileTab enum + タブ別フィード管理 + ピン留め投稿 + プロフィール内検索
│   └── SearchViewModel.swift      # タブ切り替え・Task キャンセルデバウンス + filterModeratedPosts + 検索履歴（UserDefaults）
├── Views/
│   ├── Auth/
│   │   └── LoginView.swift
│   ├── Timeline/
│   │   ├── TimelineView.swift     # FAB・返信・引用・いいね/リポストユーザー一覧遷移
│   │   └── PostCardView.swift     # モデレーション(blur/mediaBlur/filter) + 通報メニュー
│   ├── Compose/
│   │   ├── ComposeView.swift      # 返信・引用投稿・画像添付（PhotosPicker+Alt入力+クロップ）対応
│   │   └── ImageCropView.swift    # 画像クロップエディタ（オリジナル/正方形/自由、フルスクリーン）[NEW]
│   ├── Thread/
│   │   └── ThreadView.swift       # モデレーション(mediaBlur) + 通報メニュー
│   ├── Notification/
│   │   ├── NotificationListView.swift
│   │   └── NotificationItemView.swift
│   ├── Profile/
│   │   ├── ProfileView.swift      # ProfileScreenView + ProfileHeaderView + タブバー UI（4タブ）+ コンパクトヘッダー + ピン留め表示 + 内部検索バー
│   │   └── UserListView.swift     # フォロワー/フォロー中一覧 + フォロー/解除ボタン
│   ├── Search/
│   │   └── SearchView.swift       # SearchView + ActorRowView + SearchPostRowView（スレッド遷移）+ 検索履歴一覧（個別/一括削除）
│   ├── Settings/
│   │   └── SettingsView.swift     # テーマ/言語切替・via表示・モデレーション設定・Claude API キー管理・アカウント情報
│   └── Common/
│       ├── AvatarView.swift
│       ├── ImageGridView.swift    # Color.clear overlay パターン（画像はみ出し修正済み）
│       ├── ImageViewer.swift
│       ├── VideoPlayerView.swift
│       ├── LinkCardView.swift
│       ├── QuoteEmbedView.swift
│       ├── FeedSelectorView.swift  # フィード選択シート
│       ├── PostActorListView.swift # いいね/リポストユーザー一覧
│       ├── ContentWarningView.swift # PostBlurOverlay / MediaBlurOverlay
│       └── ReportView.swift        # 投稿/アカウント通報UI
├── Extensions/
│   ├── IdentifiableString.swift
│   └── String+DateFormatting.swift # relativeFormatted（相対時刻表示）
└── Documentation/
    └── tasks.md
```
