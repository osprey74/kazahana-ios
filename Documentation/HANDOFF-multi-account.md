# マルチアカウント機能 設計仕様書

> **対象プラットフォーム**: iOS / Desktop (Electron) / Android (将来)
> **作成日**: 2026-04-03
> **ステータス**: 設計確定・実装着手前

---

## 概要

1つのアプリ内で複数の Bluesky アカウントを管理し、タップ1つで切り替えられる機能。
アプリパスワードは保持せず、AT Protocol の JWT トークン（`refreshJwt`）のみを永続化する。

---

## UX フロー

### 起動時

```
アプリ起動
  ├─ 保存済みアカウント 0件
  │     → ログイン画面（従来通り）
  │
  ├─ 保存済みアカウント 1件
  │     → そのアカウントで直接ホーム（従来通り・体験変化なし）
  │
  └─ 保存済みアカウント 2件以上
        → アカウント選択画面
              ├─ アカウントをタップ → ホーム
              ├─ 「別のアカウントを追加」→ ログイン画面
              └─ アカウントを左スワイプ → 削除確認 → 削除
```

### アカウント切替（ホーム画面から）

```
設定画面 > アカウント
  ├─ ログイン中アカウント一覧（チェックマーク付き）
  │     → タップ → 切替確認なしで即時切替
  ├─ 「アカウントを追加」→ ログイン画面
  └─ アカウントを左スワイプ → 削除確認 → 削除
```

切替後の動作：
- タイムライン・通知・DM をすべてリセット・再読み込み
- アプリの状態（下書き・設定など）はアカウントをまたいで共有

### ログイン画面（追加ログイン時）

- 既存のログイン画面を流用
- ログイン成功後はそのアカウントをアクティブにしてホームへ遷移
- すでに保存済みの DID で再ログインした場合はセッションを上書き更新

---

## データモデル

### Session（変更なし）

```
Session {
  did:        String   // アカウントの一意識別子（Keychain キーとして使用）
  handle:     String   // 表示用ハンドル
  accessJwt:  String   // 短命トークン（~2時間）
  refreshJwt: String   // 長命トークン（~90日）。期限切れ時のみ再ログインが必要
  pdsHost:    String   // PDS エンドポイント
}
```

### アクティブアカウント

```
UserDefaults["activeAccountDID"] = String  // 最後にアクティブだったアカウントのDID
```

---

## ストレージ設計

### Keychain（セッション永続化）

| キー | 値 | 説明 |
|------|----|------|
| `session:{did}` | `Session` JSON | アカウントごとのセッション |

**旧キー（`session`）からの移行**:
- 初回起動時に旧形式のエントリが存在すれば `session:{did}` 形式に移行し、旧エントリを削除する

### UserDefaults

| キー | 型 | 説明 |
|------|----|------|
| `activeAccountDID` | `String` | 現在アクティブなアカウントの DID |

---

## アカウント削除の定義

| 操作 | 意味 | Keychain | サーバー側 |
|------|------|----------|-----------|
| **アカウントを削除** | このデバイスからアカウント情報を消す | 該当 DID のエントリを削除 | `deleteSession` をベストエフォートで呼び出す |
| **別アカウントに切替** | アクティブアカウントを変更する | 変更なし | 不要 |
| **ログアウト**（現行） | 廃止。「アカウントを削除」に統合 | — | — |

---

## パスワード保持ポリシー

**アプリパスワードは保持しない。**

- `refreshJwt` の有効期限は約 90 日
- 期限内はパスワード不要でアクセストークンを再発行できる
- 期限切れ時のみ再ログインダイアログを表示する
- 再ログイン成功後は `refreshJwt` を更新してそのまま継続使用

---

## プラットフォーム別実装メモ

### iOS

**変更ファイル一覧:**

| ファイル | 変更内容 |
|---------|---------|
| `Services/SessionStore.swift` | 複数セッション対応（DID キー付き保存・全件取得・個別削除・旧形式マイグレーション） |
| `ViewModels/AuthViewModel.swift` | `savedAccounts: [Session]`・`switchAccount(to:)`・`removeAccount(did:)` 追加 |
| `Views/Auth/LoginView.swift` | アカウント選択画面を追加（`AccountPickerView` として分離も可） |
| `ContentView.swift` | 起動時のアカウント数分岐ロジックを追加 |
| `Views/Settings/SettingsView.swift` | アカウント一覧・切替・削除 UI を追加 |
| `ShareExtension/ShareModels.swift` | `activeAccountDID` に基づいてアクティブセッションを読む形に変更 |

**アカウント切替時の状態リセット対象:**
- `TimelineViewModel`（フィード・カーソル・ポーリング）
- `NotificationViewModel`（未読カウント）
- `ConversationListViewModel`（DM一覧）
- `AppSettings` の `pinnedFeedURIs` / `hiddenFeedURIs`（フィード設定はアカウント共通で良ければそのまま）

**アカウント切替の実装方針:**

`AuthViewModel` 内の `ATProtoClient` は使い回す。切替時に `client.updateSession(newSession)` を呼ぶだけで以降のリクエストは新アカウントで実行される。ViewModel の再生成は `ContentView` 側で `id(did)` モディファイアを使って強制リビルドする。

```swift
// ContentView のイメージ
MainTabView(client: authVM.client)
    .id(authVM.activeAccountDID)  // DID が変わると全子ビューが再生成される
```

### Desktop (Electron / 将来)

- `electron-keytar` または OS Keychain に同じ `session:{did}` キーで保存
- `activeAccountDID` は `localStorage` または `electron-store` に保存
- UI: サイドバーにアカウントアバター一覧を表示し、タップで切替

### Android (将来)

- Android Keystore に `session:{did}` で保存
- `SharedPreferences` に `activeAccountDID` を保存

---

## 多言語対応（追加キー）

| キー | 日本語 | 英語 |
|------|--------|------|
| `auth.accountPicker.title` | アカウントを選択 | Select Account |
| `auth.accountPicker.addAccount` | 別のアカウントを追加 | Add Another Account |
| `auth.accountPicker.removeAccount` | アカウントを削除 | Remove Account |
| `auth.accountPicker.removeConfirmTitle` | アカウントを削除しますか？ | Remove this account? |
| `auth.accountPicker.removeConfirmMessage` | このデバイスからアカウント情報が削除されます。再度ログインすることで追加できます。 | Account data will be removed from this device. You can add it again by logging in. |
| `auth.switchAccount` | アカウントを切り替え | Switch Account |
| `settings.accounts` | アカウント | Accounts |
| `settings.addAccount` | アカウントを追加 | Add Account |
| `settings.activeAccount` | 使用中 | Active |

---

## 考慮事項・制約

- **IAP（サポーターバッジ）**: StoreKit のトランザクションはデバイス単位のため、アカウントをまたいで有効。現行の `AppSettings.supporterBadgeExpiryDate` はアカウントをまたいで共有で問題なし。
- **下書き（DraftService）**: Documents ディレクトリに保存されるためアカウント共通。マルチアカウント化後も変更不要。
- **BSAF設定**: `AppSettings.bsafRegisteredBots` はアカウントをまたいで共有で問題なし（bot は DID で識別されるため）。
- **Share Extension**: `activeAccountDID` で特定されたセッションのみ使用すれば十分。複数アカウント選択UIは Share Extension 内には不要。
