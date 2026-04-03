# kazahana iOS v1.1.0 — 実装引き継ぎ資料

> **作成日**: 2026-04-03  
> **バージョン**: 1.1.0 (Build 3)  
> **対象読者**: Desktop (Electron) / Android など他プラットフォーム担当者  
> **本ドキュメントの範囲**: マルチアカウント対応・関連 UX 改善の実装詳細

---

## 1. 概要

v1.1.0 では以下の機能を追加・改善した。

| 機能 | 概要 |
|------|------|
| **マルチアカウント** | 複数の Bluesky アカウントをデバイスに保存し、タップ1つで切り替え |
| **アカウント選択画面** | 複数アカウント保存時の起動画面（ブランドロゴ表示付き） |
| **ホーム画面アカウント表示** | ナビバー右上に `@handle` を表示、タップでアカウント切替 |
| **パスワード表示切替** | ログイン画面のパスワードフィールドに目のアイコン |
| **タブバー統一（iPad）** | iPad でも iPhone と同じ下部タブバーに固定 |

---

## 2. マルチアカウント: データ設計

### 2-1. セッション永続化（Keychain）

各アカウントのセッションを **DID をキーとして** 個別に保存する。

| Keychain キー | 型 | 内容 |
|---|---|---|
| `session:{did}` | JSON (Session) | アクセストークン・リフレッシュトークン・ハンドル・PDS ホスト |

**旧形式からのマイグレーション**: v1.0 では `session` という固定キーを使っていた。
初回起動時に旧キーが存在すれば `session:{did}` へ移行し、旧エントリを削除する（`SessionStore.migrateIfNeeded()`）。

```
iOS Keychain (accessGroup: 9L6A9KDH5P.com.osprey74.kazahana)
  session:did:plc:xxxxx  →  Session { did, handle, accessJwt, refreshJwt, pdsHost }
  session:did:plc:yyyyy  →  Session { ... }
```

### 2-2. アクティブアカウント管理（UserDefaults）

App Groups UserDefaults（Share Extension と共有）に以下を保存する。

| キー | 型 | 内容 |
|---|---|---|
| `activeAccountDID` | String | 現在アクティブなアカウントの DID |
| `savedAccountDIDs` | [String] | 保存済み全 DID の配列（順序保持） |

**App Groups スイート名**: `group.com.osprey74.kazahana`

### 2-3. Session モデル（変更なし）

```
Session {
  did:        String   // アカウントの一意識別子
  handle:     String   // @handle（表示用）
  accessJwt:  String   // 短命トークン（~2時間）
  refreshJwt: String   // 長命トークン（~90日）
  pdsHost:    String   // https://bsky.social など
}
```

パスワードは保持しない。`refreshJwt` が期限切れ（~90日）した場合のみ再ログインが必要。

---

## 3. マルチアカウント: 認証フロー

### 3-1. 起動時フロー

```
アプリ起動
  ├─ savedAccounts.count == 0  → ログイン画面（LoginView）
  ├─ savedAccounts.count == 1  → 自動ログイン → ホーム（体験変化なし）
  └─ savedAccounts.count >= 2  → アカウント選択画面（AccountPickerView）
```

### 3-2. アカウント切替フロー

```
切替要求（AccountPickerView / SettingsView）
  1. sessionStore.activeAccountDID = session.did   ← 先に永続化（レースコンディション防止）
  2. client.updateSession(session)                 ← 以降のAPIリクエストを新セッションで実行
  3. MainActor: savedAccounts 更新, activeAccountDID 更新, isLoggedIn = true
  4. client.refreshSessionPublic()                 ← トークンをサイレントリフレッシュ
  5. ContentView が .id(activeAccountDID) を検知 → MainTabView を再生成
     → 全 ViewModel（Timeline/Notification/DM）がリセット・再読込
```

**重要**: `sessionStore.activeAccountDID` を `client.updateSession()` より**先に**設定すること。
`client` の `onSessionUpdated` コールバックはトークンリフレッシュ後に発火し、
この時点で `sessionStore.activeAccountDID` を読み取る。順序が逆だと古い DID が返ってしまう。

### 3-3. アカウント削除フロー

```
削除要求
  1. サーバー側 deleteSession をベストエフォートで呼び出す
     POST {pdsHost}/xrpc/com.atproto.server.deleteSession
     Authorization: Bearer {refreshJwt}
  2. Keychain から session:{did} を削除
  3. savedDIDs から該当 DID を除去
  4. 削除したのがアクティブアカウントだった場合：
     - 残りアカウントがある → 先頭アカウントへ自動切替
     - 残りなし → ログイン画面へ遷移（isLoggedIn = false）
```

---

## 4. iOS 実装詳細

### 4-1. SessionStore.swift（変更内容）

```swift
// 保存: DID ごとにキーを分けて Keychain に保存
func save(_ session: Session) throws
  → Keychain key: "session:{did}"
  → savedDIDs（App Groups UserDefaults）に DID を追加
  → activeAccountDID を session.did に更新

// 全アカウント取得
func loadAll() -> [Session]
  → savedDIDs の順序通りに Keychain から Session を復元

// アクティブセッション取得
func load() -> Session?
  → activeAccountDID → load(forDID:) の順で解決

// DID 指定削除
func delete(did: String) -> Bool
  → Keychain から session:{did} を削除
  → savedDIDs から除去
  → 削除対象がアクティブなら activeAccountDID を savedDIDs.first に更新

// マイグレーション（一回限り）
private func migrateIfNeeded()
  → savedDIDs が空のとき旧キー "session" を探し session:{did} に移行
```

### 4-2. AuthViewModel.swift（変更内容）

```swift
@Observable final class AuthViewModel {
  var savedAccounts: [Session]   // 全保存アカウント一覧
  var activeAccountDID: String?  // MainTabView の .id() に使用

  // 切替
  func switchAccount(to session: Session) async

  // 削除（ログアウトも removeAccount に統合）
  func removeAccount(did: String) async

  // ログアウト（後方互換: アクティブアカウントを削除）
  func logout() async → removeAccount(did: activeAccountDID) に委譲
}
```

**ViewModel 再生成の仕組み**:
```swift
// ContentView.swift
MainTabView(client: authVM.client)
    .id(authVM.activeAccountDID)  // DID が変わると全子 View・ViewModel が再生成される
```
`ATProtoClient` インスタンスは使い回す（生成コスト回避）。
`client.updateSession()` で内部セッションを入れ替えるだけで以降のリクエストが新アカウントで実行される。

### 4-3. ContentView.swift（3ウェイ分岐）

```swift
var body: some View {
    if authVM.isLoggedIn {
        MainTabView(client: authVM.client)
            .id(authVM.activeAccountDID)
    } else if !authVM.savedAccounts.isEmpty {
        AccountPickerView()            // 複数アカウント保存済み → 選択画面
    } else {
        LoginView()                    // 新規 → ログイン画面
    }
}
```

### 4-4. AccountPickerView.swift（新規）

| 要素 | 実装 |
|------|------|
| ロゴ表示 | `.safeAreaInset(edge: .top)` でリスト上部に固定（AppLogo 72pt + "kazahana" largeTitle.bold） |
| アカウント行 | ハンドル + DID（caption2）+ 右矢印アイコン |
| 切替 | 行タップ → `authVM.switchAccount(to:)` |
| 削除 | 左スワイプ → `confirmationDialog` → `authVM.removeAccount(did:)` |
| 追加 | 「別のアカウントを追加」ボタン → `LoginView` シート |
| ナビバー | `.toolbar(.hidden)` で非表示（ロゴ表示のため） |

### 4-5. SettingsView.swift（アカウントセクション刷新）

- 全保存アカウントをリスト表示
- アクティブアカウントに `checkmark` アイコン（`.foregroundStyle(Color.accentColor)`）
- 行タップ → 即時切替（`authVM.switchAccount(to:)`）
- スワイプ削除 → `confirmationDialog` → `authVM.removeAccount(did:)`
- 「アカウントを追加」ボタン → `LoginView` シート

### 4-6. Share Extension 対応（ShareModels.swift）

Share Extension の `SessionStore.load()` を更新:
1. App Groups UserDefaults の `activeAccountDID` を取得
2. Keychain の `session:{did}` からセッションを読み込む
3. 旧キー `"session"` へのフォールバックあり（移行期対応）

---

## 5. UX 改善詳細

### 5-1. ホーム画面ナビバーにログイン中アカウント表示

**ファイル**: `Views/Timeline/TimelineView.swift`

```swift
// ナビバー右端にハンドル表示（タップで AccountPickerView）
ToolbarItem(placement: .navigationBarTrailing) {
    if let handle = authVM.client.currentSession?.handle {
        Button { showAccountSwitcher = true } label: {
            Text(abbreviatedHandle(handle))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// 22文字を超える場合は先頭21文字 + "…" に切り詰め
private func abbreviatedHandle(_ handle: String) -> String {
    let full = "@\(handle)"
    guard full.count > 22 else { return full }
    return String(full.prefix(21)) + "…"
}
```

**設計メモ**: iOS 26 の Liquid Glass ナビバーでは `frame(maxWidth:)` が ToolbarItem 内で信頼性低いため、文字数ベースの切り詰めを採用。

### 5-2. パスワード表示切替（LoginView.swift）

```swift
@State private var isPasswordVisible: Bool = false

ZStack(alignment: .trailing) {
    Group {
        if isPasswordVisible {
            TextField(placeholder, text: $password)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        } else {
            SecureField(placeholder, text: $password)
                .textContentType(.password)
        }
    }
    .textFieldStyle(.roundedBorder)

    Button { isPasswordVisible.toggle() } label: {
        Image(systemName: isPasswordVisible ? "eye" : "eye.slash")
            .foregroundStyle(isPasswordVisible ? Color.accentColor : Color.secondary)
    }
    .padding(.trailing, 8)
}
```

### 5-3. iPad タブバーを下部に固定（ContentView.swift）

iOS 18+（iPadOS）ではタブバーがデフォルトで画面上部に表示される。
iPhone と同じ下部タブバーに統一するため、`horizontalSizeClass` を compact に固定する。

```swift
TabView(selection: $selectedTab) { ... }
    .environment(\.horizontalSizeClass, .compact)
```

**設計メモ**:
- `.tabViewStyle(.tabBarOnly)` → iPadOS でも上部タブバーのまま（効果なし）
- `.environment(\.horizontalSizeClass, .compact)` → compact サイズクラスが強制され、タブバーが下部に表示される
- kazahana はモバイルファーストな SNS クライアントのため、iPad でも下部タブバーで統一

---

## 6. 多言語対応キー

`Localizable.xcstrings` に追加した i18n キー（11言語対応済み）:

| キー | 日本語 | 英語 |
|------|--------|------|
| `auth.accountPicker.title` | アカウントを選択 | Select Account |
| `auth.accountPicker.addAccount` | 別のアカウントを追加 | Add Another Account |
| `auth.accountPicker.removeAccount` | アカウントを削除 | Remove Account |
| `auth.accountPicker.removeConfirmTitle` | アカウントを削除しますか？ | Remove this account? |
| `auth.accountPicker.removeConfirmMessage` | このデバイスからアカウント情報が削除されます。再度ログインすることで追加できます。 | Account data will be removed from this device. You can add it again by logging in. |
| `settings.accounts` | アカウント | Accounts |
| `settings.addAccount` | アカウントを追加 | Add Account |

---

## 7. 他プラットフォームへの横展開ガイド

### Desktop (Electron)

| iOS の実装 | Desktop の対応 |
|---|---|
| Keychain (`session:{did}`) | `electron-keytar` または OS Keychain に同じキーで保存 |
| App Groups UserDefaults (`activeAccountDID`) | `electron-store` または `localStorage` に保存 |
| AccountPickerView（起動時） | サインイン画面またはウィンドウに「アカウント選択」セクション追加 |
| SettingsView アカウントセクション | 設定画面のアカウント管理パネル |
| `.id(activeAccountDID)` による全 View 再生成 | 切替時に State をリセット（Redux store の reset 等） |
| `switchAccount` → `client.updateSession()` | HTTP クライアントのセッションを入れ替え |
| `removeAccount` → サーバー側 deleteSession | 同様に `com.atproto.server.deleteSession` をベストエフォートで呼び出す |

**UX 推奨**: サイドバーにアカウントアバター一覧を表示し、クリックで切替。

### Android

| iOS の実装 | Android の対応 |
|---|---|
| Keychain (`session:{did}`) | Android Keystore / EncryptedSharedPreferences |
| App Groups UserDefaults | SharedPreferences |
| `migrateIfNeeded()` | 旧キーからの一回限りのマイグレーション |
| `@Observable` + `.id()` | ViewModel の `StateFlow` / LiveData をリセットして再収集 |

---

## 8. 考慮事項・制約（引き継ぎ注意事項）

### IAP（サポーターバッジ）
- StoreKit のトランザクションはデバイス単位のため**アカウント共通**。
- `AppSettings.supporterBadgeExpiryDate` は DID に関係なく有効。変更不要。

### 下書き（DraftService）
- Documents ディレクトリに保存されるためアカウント共通。変更不要。

### BSAF 設定
- `AppSettings.bsafRegisteredBots` は Bot が DID で識別されるためアカウントをまたいで共有で問題なし。

### フィード設定（pinnedFeedURIs など）
- 現状はアカウントをまたいで共有。将来的にアカウントごとに管理したい場合は `AppSettings` のキーに DID サフィックスを付ける設計変更が必要。

### Share Extension（iOS 固有）
- `activeAccountDID` で特定されたセッションのみ使用。Extension 内に複数アカウント選択 UI は不要。

### refreshJwt 期限切れ時の挙動
- 現在の実装: リフレッシュ失敗 + 保存アカウント 1件以下 → `isLoggedIn = false`（ログイン画面へ）
- 複数アカウントある場合は他アカウントには影響しない（当該アカウントのみ無効化）
- 将来改善: 期限切れアカウントを「再ログインが必要」としてグレーアウト表示する UI を追加予定

---

## 9. ファイル変更一覧（v1.1.0 差分）

| ファイル | 変更種別 | 主な変更内容 |
|---------|---------|------------|
| `Services/SessionStore.swift` | 変更 | 複数セッション対応・DID キー付き保存・旧形式マイグレーション |
| `ViewModels/AuthViewModel.swift` | 変更 | `savedAccounts`・`switchAccount(to:)`・`removeAccount(did:)` 追加 |
| `Views/Auth/AccountPickerView.swift` | **新規** | 起動時アカウント選択画面（ロゴ・アカウントリスト・追加/削除） |
| `Views/Auth/LoginView.swift` | 変更 | `@Environment(\.dismiss)` でシート dismiss 対応・パスワード表示切替追加・アプリパスワードヘルプ文削除 |
| `Views/Settings/SettingsView.swift` | 変更 | アカウントセクション刷新（マルチアカウント管理 UI）・`SettingsAccountRow` struct 抽出 |
| `Views/Timeline/TimelineView.swift` | 変更 | ナビバー右端に `@handle` 表示・`abbreviatedHandle()` ヘルパー・AccountPickerView シート |
| `ContentView.swift` | 変更 | 3ウェイ分岐ロジック・`MainTabView.id(activeAccountDID)`・`.environment(\.horizontalSizeClass, .compact)` |
| `Share Extension/ShareModels.swift` | 変更 | `activeAccountDID` ベースのセッション読み込みに変更 |
| `Localizable.xcstrings` | 変更 | `auth.accountPicker.*` 5キー + `settings.accounts` / `settings.addAccount` 追加（11言語） |
