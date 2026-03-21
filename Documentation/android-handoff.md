# kazahana Android 版 開発ハンドオフ資料

> iOS 版 kazahana の実装をもとに、Android 版開発者向けに機能仕様・技術的判断・既知の落とし穴をまとめたドキュメント。
> 最終更新: 2026-03-21（iOS 版 プロフィール・スレッド遷移改善、スワイプバック対応 完了時点）

---

## 目次

1. [アプリ概要](#1-アプリ概要)
2. [実装済み機能一覧](#2-実装済み機能一覧)
3. [AT Protocol 実装詳細](#3-at-protocol-実装詳細)
4. [アーキテクチャ方針](#4-アーキテクチャ方針)
5. [機能別実装ノート](#5-機能別実装ノート)
6. [BSAF 対応](#6-bsaf-対応)
7. [多言語対応](#7-多言語対応)
8. [既知の課題・未実装](#8-既知の課題未実装)
9. [Android 版固有の検討事項](#9-android-版固有の検討事項)

---

## 1. アプリ概要

**kazahana** は Bluesky（AT Protocol）向けのネイティブクライアント。
デスクトップ版（Web/Electron）から派生し、iOS 版は Swift/SwiftUI で一から実装した。

| 項目 | 内容 |
|---|---|
| プラットフォーム | iOS 17+ |
| 言語 | Swift 5.9 / SwiftUI |
| Bundle ID | `com.osprey74.kazahana-ios`（将来 `com.kazahana.app` に変更予定） |
| 対応言語 | 11言語: ja / en / pt / de / zh-TW / zh-CN / fr / ko / es / ru / id |
| Bluesky SNS | @app-kazahana.bsky.social |

---

## 2. 実装済み機能一覧

### コア機能
| 機能 | 状態 | 備考 |
|---|---|---|
| ログイン / セッション管理 | ✅ | PDS 解決付き |
| ホームタイムライン | ✅ | cursor ページネーション + 無限スクロール |
| Pull-to-Refresh | ✅ | |
| タイムライン自動更新 | ✅ | ポーリング間隔 30/60/90/120秒、設定可 |
| いいね / リポスト | ✅ | 楽観的 UI 更新（タップ即時反映・失敗時ロールバック） |
| 引用投稿 | ✅ | |
| スレッド表示 | ✅ | 親チェーン再帰・フォーカス投稿・返信一覧 |
| 投稿作成 | ✅ | 300文字（grapheme 単位） |
| 返信 | ✅ | |
| 画像添付（最大4枚） | ✅ | クロップ・ALT テキスト付き |
| 動画添付 | ✅ | MP4/MOV、video.bsky.app 経由アップロード |
| リッチテキスト表示 | ✅ | メンション・URL・ハッシュタグ自動検出 Facet 化 |
| 画像フルスクリーン表示 | ✅ | ページング・ピンチ/ダブルタップズーム |
| 動画再生 | ✅ | HLS ストリーミング |

### ソーシャル機能
| 機能 | 状態 | 備考 |
|---|---|---|
| プロフィール表示 | ✅ | 7タブ（投稿/返信/メディア/いいね/フィード/リスト/スターターパック） |
| フォロー / フォロー解除 | ✅ | 楽観的 UI |
| フォロワー/フォロー中一覧 | ✅ | フォロー/解除ボタン付き |
| ピン留め投稿表示 | ✅ | |
| プロフィール内検索 | ✅ | |
| ユーザー検索 + 投稿検索 | ✅ | Task キャンセルでデバウンス |
| 検索履歴 | ✅ | UserDefaults 永続化、最大20件 |
| カスタムフィード閲覧 | ✅ | |
| リストフィード閲覧 | ✅ | |
| スターターパック閲覧 | ✅ | |
| 通知一覧 + 未読バッジ | ✅ | リポスト経由いいねにも対応 |
| ダイレクトメッセージ（DM） | ✅ | chat.bsky.convo.* |
| メンションオートコンプリート | ✅ | `searchActorsTypeahead` |

### 投稿作成オプション
| 機能 | 状態 | 備考 |
|---|---|---|
| スレッドゲート（返信制限） | ✅ | 全員/メンション/フォロワー/フォロー中/不可 の7種 |
| ポストゲート（引用制限） | ✅ | |
| 下書き保存 | ✅ | 最大20件、画像/動画メタデータ含む |
| スレッド投稿（複数連投） | ❌ | ペンディング（デスクトップ版でも見送り） |

### モデレーション
| 機能 | 状態 | 備考 |
|---|---|---|
| ラベルベースモデレーション | ✅ | 5段階: none/inform/mediaBlur/blur/filter |
| 成人向けコンテンツ設定 | ✅ | |
| コンテンツ警告オーバーレイ | ✅ | |
| 投稿通報 | ✅ | `com.atproto.moderation.createReport` |
| アカウント通報 | ✅ | |

### プラットフォーム固有機能
| 機能 | 状態 | 備考 |
|---|---|---|
| Share Extension（受信） | ✅ | 他アプリから共有 → 投稿 |
| 共有シート（送信） | ✅ | 投稿 URL を他アプリに共有 |
| ディープリンク | ✅ | `kazahana://profile/` `kazahana://post/` `kazahana://hashtag/` |
| バックグラウンドポーリング | ✅ | BGAppRefreshTask + ローカル通知 |

### 設定・カスタマイズ
| 機能 | 状態 | 備考 |
|---|---|---|
| テーマ（ライト/ダーク/システム） | ✅ | |
| 投稿言語設定 | ✅ | |
| アプリ表示言語切り替え | ✅ | 再起動方式（UserDefaults AppleLanguages） |
| via 表示（クライアント名付与） | ✅ | "kazahana for iOS" |
| ホームフィード管理 | ✅ | 表示/非表示トグル・ドラッグ並び替え |
| Claude API キー登録 | ✅ | ALT テキスト自動生成用 |

### kazahana 独自機能
| 機能 | 状態 | 備考 |
|---|---|---|
| BSAF 対応 | ✅ | Bot による構造化投稿フィルタ・重複検出 |
| Bot ラベルバッジ | ✅ | `label.val == "bot"` 判定でアイコン表示 |
| サポーターバッジ IAP | ✅ コード実装済み | App Store Connect 商品登録はユーザー作業 |

---

## 3. AT Protocol 実装詳細

### 認証フロー

```
1. ユーザーが handle を入力
2. `/.well-known/atproto-did` で DID を解決
   → 失敗時: `plc.directory/{did}` で解決
   → 最終フォールバック: bsky.social PDS を使用
3. PDS エンドポイントを解決して `com.atproto.server.createSession` を呼び出す
4. accessJwt + refreshJwt を Keychain に保存
5. 401 レスポンス時: refreshJwt で `com.atproto.server.refreshSession` を呼び出し自動リトライ（1回のみ）
```

**重要**: `refreshSession` は `refreshJwt` を Bearer トークンとして使用する（`accessJwt` ではない）。

### レート制限

429 レスポンス時: `retry-after` ヘッダーを参照して指数バックオフ（最大3回）。

### チャット API（DM）

Bluesky のチャット API は通常の XRPC とは異なるプロキシエンドポイントを使用する:

```
ヘッダー: atproto-proxy: did:web:api.bsky.chat#bsky_chat
エンドポイント: https://api.bsky.app/xrpc/chat.bsky.convo.*
```

iOS 版では `ATProtoClient.getWithProxy()` / `postWithProxy()` として実装した。

### 動画アップロード

動画は通常の `uploadBlob` ではなく、専用サービスを使用する:

```
1. ATProtoClient.getServiceAuth(audience: "did:web:video.bsky.app") でサービストークン取得
2. https://video.bsky.app/xrpc/app.bsky.video.uploadVideo へ POST
3. ジョブ ID を受け取り、app.bsky.video.getJobStatus でポーリング（完了まで待機）
4. 完了後に BlobRef を取得し embed に使用
```

**落とし穴**: `AVAssetExportSession` を使った変換処理はバックグラウンド遷移で中断されるため、生データを直接アップロードする方式に変更した。

### via フィールド

`PostRecord` に `$via` フィールドを追加してクライアント名を記録する。
CodingKey は `"$via"`（`$` プレフィックスに注意）。

### Facet（リッチテキスト）

Bluesky の Facet は UTF-8 バイトオフセットで範囲を指定する（Swiftの String.Index や Unicode code unit ではない）。
文字列を `Data(string.utf8)` に変換してバイト位置を計算する必要がある。

自動検出の順序: URL → メンション → ハッシュタグ（重複した場合は先行するものを優先）。

---

## 4. アーキテクチャ方針

### iOS 版のアーキテクチャ

```
View ──@Environment──> ViewModel (@Observable)
                            │
                            ▼
                       Service Layer
                            │
                            ▼
                       ATProtoClient (URLSession + async/await)
```

- **状態管理**: `@Observable` (iOS 17+ Observation framework)
- **DI**: `@Environment` 経由で ViewModel / Service を伝播
- **HTTP**: `URLSession` + `async/await`（Combine 不使用）
- **永続化**: Keychain（セッション情報）、UserDefaults（設定・履歴）
- **楽観的 UI**: タップ直後にローカル状態を更新し、API 失敗時にロールバック

### Android 版での対応推奨

| iOS | Android 推奨 |
|---|---|
| `@Observable` ViewModel | `ViewModel` + `StateFlow` / `MutableStateFlow` |
| `@Environment` DI | Hilt または手動 DI |
| `URLSession` + async/await | `Retrofit` + `coroutines` / `OkHttp` |
| `UserDefaults` | `DataStore` (Preferences) |
| `Keychain` | `EncryptedSharedPreferences` or `Keystore` |
| `SwiftUI NavigationStack` | Compose Navigation |
| `sheet(item:)` | `ModalBottomSheet` / `Dialog` |

---

## 5. 機能別実装ノート

### タイムライン

- **ポーリング**: `Task` + `try await Task.sleep` で実装。設定変更時は既存タスクをキャンセルして再起動。
- **フィルタリング**: `filterAndProcessPosts()` パイプラインで以下を順に処理:
  1. BSAF 重複検出（`type|value|time|target` キーでグループ化）
  2. モデレーション（`filter` 判定の投稿を除外）
  3. BSAF フィルタ（Bot フィルタ設定に合致しない投稿を除外）
- **FeedSource**: `.following` / `.custom(GeneratorView)` / `.list(GraphListView)` の3種

### プロフィール画面

- 7タブ（投稿/返信/メディア/いいね/フィード/リスト/スターターパック）で各タブのフィードを個別にキャッシュ
- スクロール位置を監視してコンパクトヘッダーを表示切り替え（iOS は `onScrollGeometryChange` を使用）
- **ピン留め投稿**: `ProfileView.pinnedPost?.record.uri` → `PostService.getPosts(uris:)` で取得
- `isSelf` 判定: `currentSession.did == actor`（actor は DID または handle）

### 投稿カード（PostCardView）

多くの表示バリアントが一つのコンポーネントに集約されている:

- 通常表示 / モデレーションブラー / メディアブラー
- BSAF 左ボーダー（深刻度カラー）
- BSAF タグバッジ（折り返しフローレイアウト）
- BSAF 重複インジケーター
- Bot ラベルバッジ
- 三点メニュー（翻訳・コピー・共有・削除・通報）
- 著者名タップ → プロフィール遷移（`onTapAuthor: ((String) -> Void)?` コールバック）

### プロフィール・スレッド画面のナビゲーション

iOS 版はナビバーを `.toolbar(.hidden, for: .navigationBar)` で非表示にしており、以下の方式で代替している:

- **カスタム戻るボタン**: `chevron.left`・36×36pt・`ultraThinMaterial` 円形背景を `.overlay(alignment: .topLeading)` で表示
- **スワイプバック復活**: `UIViewControllerRepresentable` ベースのヘルパー（`View+InteractivePop.swift`）で `interactivePopGestureRecognizer.isEnabled = true` を `viewWillAppear` で設定

Android 版では `Scaffold` + `TopAppBar` の `navigationIcon` に戻るボタンを配置する方式が一般的。スワイプバックは `BackHandler` または Navigation Component の標準挙動を活用。

### DM（ダイレクトメッセージ）

- ポーリング: メッセージ一覧 15秒、未読数・会話一覧 30秒
- 既読処理: `chat.bsky.convo.updateRead` をメッセージ一覧表示時に自動呼び出し
- メッセージ削除は自分側のみ（`deleteMessageForSelf`）

### Share Extension / 共有機能（iOS 固有）

Android では `Intent` / `IntentFilter` で同等の機能を実装できる。
キーポイント:
- セッション情報（Keychain）を共有 → Android: `EncryptedSharedPreferences` + 同一署名でのプロセス間共有
- 設定情報（UserDefaults App Groups）を共有 → Android: `ContentProvider` または同一プロセス内

### 画像処理

- **クロップ**: 3モード（オリジナル比率 / 正方形 / 自由変形）、4隅ハンドル + 内部ドラッグ移動
- **ALT テキスト**: 各画像に個別設定、Claude API で自動生成オプション付き
- **アスペクト比**: 1枚画像は `aspectRatio` が既知なら `scaledToFit`（最大400dp相当）、不明時は固定高
- **複数枚グリッド**: 2枚=横2分割、3枚=左1枚+右2段、4枚=2×2グリッド

### 通知

- **リポスト経由いいね**: `like-via-repost` reason → `com.atproto.repo.getRecord` で repost レコード取得 → 元投稿 URI を解決
- 未読バッジ: タブアイコンに表示

---

## 6. BSAF 対応

BSAF（Bluesky Structured Alert Feed）は kazahana 独自の機能拡張。詳細仕様: `../bsaf-protocol/docs/bsaf-spec-ja.md`

### 概要

Bot が投稿する `tags` フィールドに `bsaf:v1` プレフィックスの構造化メタデータを埋め込む。
クライアントはこれをパースしてフィルタリング・表示を行う。

### タグフォーマット

```
bsaf:v1        ← バージョンマーカー（必須）
type:quake     ← イベント種別
value:4        ← 値（例: 震度）
time:20260321T120000Z  ← 発生時刻（ISO8601）
target:tokyo   ← 対象地域
source:botid   ← Bot 識別子
```

### Bot Definition JSON

Bot が公開する JSON ファイル（`self_url` で指定）:

```json
{
  "bsaf_schema": "1.0",
  "updated_at": "2026-01-01T00:00:00Z",
  "self_url": "https://example.com/bot-def.json",
  "bot": {
    "handle": "quake-bot.bsky.social",
    "did": "did:plc:xxxxx",
    "name": "地震速報Bot",
    "description": "...",
    "source": "気象庁",
    "source_url": "https://www.jma.go.jp/"
  },
  "filters": [
    {
      "tag": "value",
      "label": "震度",
      "options": [
        { "value": "1", "label": "震度1" },
        { "value": "2", "label": "震度2" }
      ]
    }
  ]
}
```

### クライアント側の実装ポイント

1. **Bot 登録**: URL 入力 → `URLSession` で JSON 取得 → バリデーション → `AppSettings` に保存 → Bot を自動フォロー
2. **フィルタリング**: 各 filter の tag について、ユーザーが有効にした value セットに投稿の tag 値が含まれるか（AND 条件）
3. **重複検出**: `type|value|time|target` を重複キーとしてグループ化。同一イベントを複数 Bot が報告した場合、先頭のみ表示し残りは折りたたむ
4. **深刻度カラー**:
   - `type:quake` + `value:5-` 以上 → 赤、4 → オレンジ、それ以下 → 緑
   - `type:warning` → ピンク/オレンジ/黄/青（レベルに応じて）
5. **自動更新**: アプリ起動時に登録済み Bot の `self_url` を取得し `updated_at` を比較、変更があれば定義を更新（ユーザーのフィルタ設定はマージして保持）

### 永続化

`BsafRegisteredBot` を JSON エンコードして `UserDefaults` に保存:

```kotlin
// Android 対応例
data class BsafRegisteredBot(
    val definition: BsafBotDefinition,
    val filterSettings: Map<String, List<String>>,
    val registeredAt: String,  // ISO8601
    val lastCheckedAt: String
)
```

---

## 7. 多言語対応

### 対応言語

ja / en / pt / de / zh-TW / zh-CN / fr / ko / es / ru / id（11言語）

### 翻訳ソース

デスクトップ版の翻訳ファイル `../kazahana/src/i18n/locales/*.json` を流用。
iOS 版は `.xcstrings` (String Catalog) 形式に変換して管理。

Android 版では各言語の `strings.xml` に変換することを推奨。

### キー命名規則

```
{機能}.{項目}

例:
settings.theme         → テーマ設定
bsaf.title             → BSAF タイトル
iap.purchase           → IAP 購入ボタン
profile.noPosts        → 投稿なし表示
common.cancel          → キャンセル
```

### 重要キーカテゴリ

| プレフィックス | 内容 |
|---|---|
| `common.*` | 汎用UI（キャンセル、確認、削除など） |
| `settings.*` | 設定画面 |
| `profile.*` | プロフィール画面 |
| `timeline.*` | タイムライン |
| `compose.*` | 投稿作成 |
| `notification.*` | 通知 |
| `dm.*` | ダイレクトメッセージ |
| `moderation.*` | モデレーション |
| `bsaf.*` | BSAF 機能（23キー） |
| `iap.*` | IAP（8キー） |
| `bot.*` | Bot ラベルバッジ |
| `lang.*` | 言語名 |
| `tab.*` | タブバー |

---

## 8. 既知の課題・未実装

### コードベースの課題

| 課題 | 詳細 |
|---|---|
| **スレッド投稿** | 複数ポストを繋いで一括投稿。デスクトップ版でも見送り中。ペンディング |
| **ブックマーク** | AT Protocol にネイティブ API がない。設計要検討（ローカル保存 or 独自リスト） |
| **画像キャッシュライブラリ** | 現在 `AsyncImage`（iOS 標準）を使用。パフォーマンス改善のため Coil（Android）等の専用ライブラリ検討推奨 |
| **検索デバウンス** | Task キャンセルで対処中だが、厳密な時間ベースのデバウンスは未実装 |
| **Unit Tests** | モデル・サービス層のテストがほぼ空 |

### IAP（サポーターバッジ）

- コードは実装済み（`IAPService.swift`）
- App Store Connect での商品登録（product ID: `com.kazahana.app.supporter_badge_30d`）は未完了
- Android 版は Google Play の課金 API（`BillingClient`）に相当実装が必要

---

## 9. Android 版固有の検討事項

### ディープリンク

iOS: カスタム URL スキーム `kazahana://`

Android では以下の2方式を検討:
- カスタムスキーム `kazahana://`（iOS と同様）
- App Links（`https://` + `assetlinks.json`）→ Bluesky が `bsky://` と `bsky.app` の両方を使っているように

### 通知

iOS: `BGAppRefreshTask` + `UNUserNotificationCenter`

Android:
- フォアグラウンド: ポーリング
- バックグラウンド: `WorkManager` で定期実行
- プッシュ通知: Firebase Cloud Messaging (FCM) の導入も検討（iOS 版は未実装）

### ウィジェット

iOS 版は未実装だが Android はホーム画面ウィジェットが標準的。将来機能として検討可。

### 命名衝突（iOS で解決済み、Android でも注意）

| 問題 | iOS の解決策 | Android 版での注意 |
|---|---|---|
| `Label`（SwiftUI）vs `Label`（ATProto）| `ContentLabel` に改名 | Android 標準の `TextView` 等との衝突確認 |
| `ProfileView`（SwiftUI）vs `ProfileView`（ATProto）| `ProfileScreenView` に改名 | Compose の `@Composable fun` 命名で同様の衝突が起きる場合がある |
| `PostEmbed` 循環参照 | `indirect enum` + `PostRecordSimple` | Kotlin では sealed class + 前方参照で解決 |
| `ThreadViewPost` 再帰 struct | `final class` に変更 | Kotlin の `data class` は再帰不可なので `class` を使用 |

### Facet（リッチテキスト）の UTF-8 オフセット

Android/Kotlin での計算方法:

```kotlin
fun String.utf8ByteOffset(charIndex: Int): Int {
    return this.substring(0, charIndex).toByteArray(Charsets.UTF_8).size
}
```

Bluesky の Facet は **UTF-8 バイトオフセット**で範囲を指定する。
Kotlin の `String.indices` や `CharSequence` の index は **UTF-16 code unit** なので変換が必要。絵文字・CJK 文字で特にズレが生じる。

### 動画アップロード（Android）

iOS 版の実装:
1. フォトライブラリから動画を `Data` として直接ロード（`AVAsset` でのトランスコードは非推奨）
2. `video.bsky.app` にアップロード → ジョブポーリング

Android 版でも `ContentResolver` から URI でバイト列を直接読み込み、リトライ可能な `OkHttp` リクエストでアップロードする方式を推奨。`MediaMuxer` による再エンコードはバックグラウンド遷移で中断するリスクがある。

---

## 参考リンク・ソース

- **iOS 版リポジトリ**: `../kazahana-ios/`
- **デスクトップ版ソース**: `../kazahana/`
- **BSAF プロトコル仕様**: `../bsaf-protocol/docs/bsaf-spec-ja.md`
- **モバイル仕様書**: `../kazahana/design/kazahana-mobile-spec.md`
- **AT Protocol 公式**: https://atproto.com/
- **Bluesky API リファレンス**: https://docs.bsky.app/
