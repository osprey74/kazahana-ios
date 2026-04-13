// AuthViewModel.swift
// kazahana-ios
// 認証状態管理 ViewModel（マルチアカウント対応）

import SwiftUI
import Observation

@Observable
final class AuthViewModel {

    // MARK: - State

    var isLoggedIn: Bool = false
    var isLoading: Bool = false
    var errorMessage: String? = nil

    /// 保存済みの全アカウント
    var savedAccounts: [Session] = []

    /// 現在アクティブなアカウントの DID（MainTabView の .id() に使用）
    var activeAccountDID: String? = nil

    // MARK: - Dependencies

    let client: ATProtoClient
    private let sessionStore: SessionStore
    private let authService: AuthService

    // MARK: - Init

    init() {
        let sessionStore = SessionStore()
        let client = ATProtoClient(sessionStore: sessionStore)
        self.sessionStore = sessionStore
        self.client = client
        self.authService = AuthService(client: client)

        let accounts = sessionStore.loadAll()
        self.savedAccounts = accounts

        if accounts.count == 1 {
            // 1アカウントのみ：自動ログイン
            self.activeAccountDID = accounts[0].did
            self.isLoggedIn = client.currentSession != nil
            if client.currentSession != nil {
                Task {
                    await refreshSessionOnLaunch()
                    // 通知許可を求め、保存済みトークンがあれば全アカウントに再登録
                    await PushNotificationService.shared.requestPermission()
                    await PushNotificationService.shared.registerTokenForAllAccounts()
                }
            }
        } else if accounts.count > 1 {
            // 複数アカウント：アカウント選択画面を表示（isLoggedIn = false）
            self.activeAccountDID = sessionStore.activeAccountDID
            self.isLoggedIn = false
        }
        // 0アカウント：isLoggedIn = false のまま（LoginView を表示）

        // セッション更新コールバック（ATProtoClient の 401 自動ログアウトに対応）
        client.onSessionUpdated = { [weak self] session in
            Task { @MainActor in
                guard let self else { return }
                self.savedAccounts = sessionStore.loadAll()
                self.activeAccountDID = sessionStore.activeAccountDID
                if session == nil && self.savedAccounts.isEmpty {
                    self.isLoggedIn = false
                }
            }
        }
    }

    // MARK: - ログイン

    func login(identifier: String, password: String) async {
        guard !identifier.isEmpty, !password.isEmpty else {
            errorMessage = String(localized: "auth.missingCredentials")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            _ = try await authService.login(identifier: identifier, password: password)
            await MainActor.run {
                savedAccounts = sessionStore.loadAll()
                activeAccountDID = sessionStore.activeAccountDID
                isLoggedIn = true
            }
            // 通知許可を求め、デバイストークンをバックエンドに登録
            let did = sessionStore.activeAccountDID ?? ""
            await PushNotificationService.shared.requestPermission()
            await PushNotificationService.shared.registerToken(for: did)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - アカウント切替

    /// 保存済みアカウントに切り替える
    func switchAccount(to session: Session) async {
        // ストアを先に永続化（refreshSession 後のコールバックが古い DID を返さないように）
        sessionStore.activeAccountDID = session.did
        client.updateSession(session)
        // タイムラインと並走させると期限切れトークンで競合するため、
        // リフレッシュを先に完了させてからログイン状態にする
        do {
            try await client.refreshSessionPublic()
        } catch {
            client.updateSession(nil)
        }
        await MainActor.run {
            savedAccounts = sessionStore.loadAll()
            activeAccountDID = sessionStore.activeAccountDID ?? session.did
            isLoggedIn = client.currentSession != nil
        }
        guard client.currentSession != nil else { return }
        // 通知許可を求め、切替先アカウントのデバイストークンをバックエンドに登録
        await PushNotificationService.shared.requestPermission()
        await PushNotificationService.shared.registerToken(for: session.did)
    }

    // MARK: - アカウント削除

    /// 指定 DID のアカウント情報をデバイスから削除する
    func removeAccount(did: String) async {
        // サーバー側セッション削除（ベストエフォート）
        if let session = sessionStore.load(forDID: did) {
            let url = URL(string: "\(session.pdsHost)/xrpc/com.atproto.server.deleteSession")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(session.refreshJwt)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)
        }

        // プッシュ通知トークンをバックエンドから削除（ベストエフォート）
        await PushNotificationService.shared.unregisterToken(for: did)

        let isRemovingActive = (did == (sessionStore.activeAccountDID ?? ""))
        sessionStore.delete(did: did)
        let remaining = sessionStore.loadAll()

        await MainActor.run {
            savedAccounts = remaining
            if isRemovingActive {
                if let next = remaining.first {
                    // 別のアカウントへ自動切替
                    client.updateSession(next)
                    activeAccountDID = next.did
                    isLoggedIn = true
                } else {
                    // 全アカウント削除 → ログイン画面へ
                    client.updateSession(nil)
                    activeAccountDID = nil
                    isLoggedIn = false
                }
            }
        }
    }

    // MARK: - ログアウト（後方互換：アクティブアカウントを削除）

    func logout() async {
        guard let did = sessionStore.activeAccountDID else { return }
        await removeAccount(did: did)
    }

    // MARK: - Private

    /// 起動時のトークンリフレッシュ（サイレント失敗）
    private func refreshSessionOnLaunch() async {
        do {
            try await client.refreshSessionPublic()
        } catch {
            // リフレッシュ失敗時：セッションを無効化（再ログインが必要）
            if sessionStore.loadAll().count <= 1 {
                await MainActor.run { isLoggedIn = false }
                client.updateSession(nil)
            }
        }
    }
}
