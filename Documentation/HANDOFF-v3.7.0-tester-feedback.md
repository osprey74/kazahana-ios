# kazahana iOS v3.7.0 — テスターフィードバック対応引き継ぎ資料

> **作成日**: 2026-06-24
> **対象バージョン**: 3.7.0 (Build TBD)
> **対象読者**: 次回開発セッション担当者
> **本ドキュメントの範囲**: v3.6.0 テスターフィードバックへの対応詳細と残課題

---

## 1. 概要

v3.6.0 (Build 22) のテスト結果として iOS/macOS 合わせて 15 件の課題が報告された。
本セッションで全件に対応し、ビルド成功を確認済み。一部はテスター再テスト待ち。

---

## 2. iOS版 対応一覧

### 2-1. フリック vs タップ誤認識

- **ファイル**: `kazahana-ios/Views/Timeline/TimelineView.swift`
- **変更**: `DragGesture(minimumDistance: 50)` → `minimumDistance: 20` に変更。ジェスチャー検出を早期開始しタップ誤認識を防止。`onEnded` 内で `abs(horizontal) > 50` の最低移動量チェックを追加し誤スワイプを防止。角度制限を 1.5 → 2.0 に厳格化。

### 2-2. 画像拡大後のスクロール改善

- **ファイル**: `kazahana-ios/Views/Common/ImageViewer.swift`
- **変更**:
  - ピンチ+ドラッグを `SimultaneousGesture` → ピンチは常時有効、ドラッグは `isZoomed` 時のみ有効に分離。等倍時は TabView のスワイプに委譲。
  - パンにバウンド制限追加（`clampedOffset`）、スプリングアニメーションでスナップバック。最大ズーム 5.0x 制限。
  - ページインジケーター（ドット）が ALT テキストに覆われる問題を ZStack → VStack 配置に変更して解消。
  - 前後2枚の画像をプリフェッチ（`URLSession` でキャッシュに載せる）して3枚目の読み込み遅延を改善。

---

## 3. macOS版 対応一覧

### 3-1. 返信ボタンが新規投稿になる問題

- **ファイル**: `kazahana-ios/Views/Timeline/TimelineView.swift`
- **変更**: `replyToPost` と `showCompose` の設定を分離。`replyToPost = post` 設定後、`DispatchQueue.main.async { showCompose = true }` で次フレームに遅延させてレースコンディションを回避。
- **補足**: 当初 `ComposeAction` enum + `sheet(item:)` パターンに変更したが、macOS Catalyst で FAB が反応しなくなる問題が発生し、元の `sheet(isPresented:)` パターンに戻した。

### 3-2. フォントサイズ設定の適用拡大

- **ファイル群**:
  - `kazahana-ios/Services/AppSettings.swift` — `FontSize` enum に `uiFont: UIFont` プロパティ追加
  - `kazahana-ios/Views/Notification/NotificationItemView.swift` — 投稿本文 + フォールバックテキストに `fontSize.bodyFont` 適用
  - `kazahana-ios/Views/Messages/ChatThreadView.swift` — メッセージ本文 + 入力欄に `fontSize.bodyFont` 適用
  - `kazahana-ios/Views/Messages/ConversationListView.swift` — メッセージプレビューに `fontSize.bodyFont` 適用
  - `kazahana-ios/Views/Compose/ComposeView.swift` — iOS: TextEditor、macOS: CatalystTextEditor の UITextView フォントに適用
- **設定UIの場所**: プロフィール画面 → ⚙️ → 表示設定セクション内（`SettingsView.swift:49`）

### 3-3. リンクカード（OGP）の改善

- **問題1**: Edge/Safari 共有時にリンクカードが自動生成されない
  - **ファイル**: `kazahana-ios/Views/Compose/ComposeView.swift`
  - **変更**: `.task` 修飾子を追加し、`initialText` に含まれる URL を検出して自動的に OGP フェッチ。iOS/macOS 両対応。

- **問題2**: リンクカードに URL とタイトルしか表示されない（画像・説明文なし）
  - **根本原因**: Share Extension (`ShareATProtoClient.swift`) の OGP 正規表現に末尾の余分な `"` があり、`og:image` と `og:description` が一切マッチしなかった。
  - **ファイル**:
    - `ShareExtension/ShareATProtoClient.swift` — `ogValue` / `metaDescription` の正規表現バグ修正
    - `kazahana-ios/Services/LinkPreviewService.swift` — `ogValue` を `name` 属性対応に拡張
  - **共通改善**: `twitter:title` / `twitter:description` / `twitter:image` フォールバック追加、プロトコル相対URL (`//cdn.example.com/...`) 対応
  - **検証**: Yahoo News (`news.yahoo.co.jp`) の OGP タグで title/description/image の全抽出を確認済み。

### 3-4. 投稿フォームのメディア添付（macOS Catalyst）

macOS Catalyst の投稿フォーム下部ツールバーを大幅に再構成。

- **最終形**: 写真/ビデオの2ボタンを **統合メディアボタン** 1つに集約
  - アイコン: `photo.on.rectangle.angled`
  - 未選択時: Finder で画像＋動画を選択可能（`[.image, .movie]`）
  - 画像選択済み: 画像のみ追加可（`[.image]`）
  - 画像10枚 or 動画選択済み: ボタン無効

- **実装**: `CatalystMediaPicker` (enum, ComposeView.swift 内)
  - `UIDocumentPickerViewController` を `keyWindow` の最上位 VC から present
  - 結果は `NotificationCenter` 経由で SwiftUI に通知
  - delegate は static プロパティで強参照保持

- **クリップボード画像ペースト**: `CatalystTextEditor` の `SubmitTextView` で `paste:` をオーバーライドし、`UIPasteboard.general.images` をインターセプト

- **クラッシュ修正の経緯**:
  1. `UIDocumentPickerViewController` が macOS Catalyst のサンドボックスでクラッシュ → **エンタイトルメント `com.apple.security.files.user-selected.read-only` を追加**（`kazahana-ios.entitlements`）
  2. `windowLevel` でソートして最高レベルのウィンドウから present → キーボード入力ウィンドウ（`UIInputWindowController`）から表示されてしまう → **`scene.keyWindow` に変更**
  3. `.onDrop` 修飾子が macOS Catalyst でボタンクリックを奪う → **`.onDrop` を削除**（ドラッグ&ドロップは Cmd+V ペーストで代替）

- **アイコンのクリック範囲**: 全ツールバーアイコンに `.frame(width: 32, height: 32)` + `.contentShape(Rectangle())` を追加し、SF Symbols の透明部分もクリック可能に。

### 3-5. Share Extension

- **表示名修正**: `project.pbxproj` の `INFOPLIST_KEY_CFBundleDisplayName` + `ShareExtension/Info.plist` に `CFBundleDisplayName = kazahana` を設定。**クリーンビルド + macOS 再起動**が必要。

### 3-6. タイムラインのデータ解析エラー

- **ファイル**: `kazahana-ios/Models/Post.swift`
- **変更**:
  - `TimelineResponse` のデコードに `SafeDecodable<FeedViewPost>` ラッパーを導入。個別投稿のデコード失敗をスキップし、タイムライン全体の表示を維持。
  - `PostEmbed` の全 embed 型（images, gallery, external, record, recordWithMedia, video）に try/catch フォールバック追加。デコード失敗時は `.unknown` にフォールバック。
  - `TimelineResponse` に通常の `init(feed:cursor:)` イニシャライザを追加（空レスポンス生成用）。

---

## 4. 変更ファイル一覧

| ファイル | 変更内容 |
|---------|---------|
| `kazahana-ios/Views/Timeline/TimelineView.swift` | フリックジェスチャー改善、返信レースコンディション修正 |
| `kazahana-ios/Views/Common/ImageViewer.swift` | ズーム・スクロール・プリフェッチ・レイアウト改善 |
| `kazahana-ios/Views/Compose/ComposeView.swift` | macOS メディアピッカー統合、ペースト対応、フォントサイズ、リンクカード自動生成、ツールバー改善 |
| `kazahana-ios/Views/Notification/NotificationItemView.swift` | フォントサイズ適用 |
| `kazahana-ios/Views/Messages/ChatThreadView.swift` | フォントサイズ適用 |
| `kazahana-ios/Views/Messages/ConversationListView.swift` | フォントサイズ適用 |
| `kazahana-ios/Services/AppSettings.swift` | `uiFont` プロパティ追加 |
| `kazahana-ios/Services/LinkPreviewService.swift` | OGP パース改善 |
| `kazahana-ios/Models/Post.swift` | SafeDecodable、PostEmbed フォールバック |
| `kazahana-ios/kazahana-ios.entitlements` | `files.user-selected.read-only` 追加 |
| `kazahana-ios.xcodeproj/project.pbxproj` | Share Extension 表示名修正 |
| `ShareExtension/Info.plist` | CFBundleDisplayName 追加 |
| `ShareExtension/ShareATProtoClient.swift` | OGP 正規表現バグ修正、パース改善 |

---

## 5. 未確認・残課題

| # | 項目 | 状態 |
|---|------|------|
| 1 | Share Extension 名前「kazahana」表示 | クリーンビルド + macOS 再起動後に確認 |
| 2 | Share Extension リンクカード生成 | OGP バグ修正済み、テスター再テスト待ち |
| 3 | 返信レースコンディション | 修正済み、テスター再テスト待ち |
| 4 | タイムラインパースエラー解消 | SafeDecodable 導入済み、テスター再テスト待ち |
| 5 | ドラッグ&ドロップ | `.onDrop` が macOS Catalyst でクリック干渉するため削除。将来的に別の実装方法を検討（`NSDropTargetView` 等）|
| 6 | バージョン番号更新 | 未実施（テスト完了後に実施） |
| 7 | tasks.md 更新 | 未実施 |

---

## 6. 学んだ macOS Catalyst の注意点

今回の対応で判明した macOS Catalyst 固有の問題を記録する。

1. **`UIDocumentPickerViewController` にはサンドボックスエンタイトルメントが必須**: `com.apple.security.files.user-selected.read-only` がないとクラッシュする。
2. **`scene.windows` の windowLevel ソートは危険**: キーボード入力ウィンドウ（`UIInputWindowController`）が最高レベルのため、`scene.keyWindow` を使うべき。
3. **SwiftUI の `.onDrop` はボタンクリックを奪う**: macOS Catalyst では `.onDrop` をビュー全体に適用するとボタンが反応しなくなる。テキスト入力エリアのみに限定するか、別の方法を使う必要がある。
4. **SwiftUI の `PhotosPicker` はキャンセル不可**: macOS Catalyst では ESC 以外の閉じ手段がなく、UX が悪い。`UIDocumentPickerViewController`（Finder ダイアログ）に置き換えが推奨。
5. **SF Symbols アイコンの透明部分はクリック不能**: `.contentShape(Rectangle())` + `.frame()` でタップ領域を確保する必要がある。
