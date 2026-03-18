// AuthViewModel.swift
// kazahana-ios
// 認証状態管理 ViewModel

import SwiftUI
import Observation

@Observable
final class AuthViewModel {

    // MARK: - State

    var isLoggedIn: Bool = false
    var isLoading: Bool = false
    var errorMessage: String? = nil

    // MARK: - Dependencies

    let client: ATProtoClient
    private let authService: AuthService

    // MARK: - Init

    init() {
        let sessionStore = SessionStore()
        let client = ATProtoClient(sessionStore: sessionStore)
        self.client = client
        self.authService = AuthService(client: client)

        // 起動時に保存済みセッションがあればログイン済み状態にする
        self.isLoggedIn = client.currentSession != nil

        // セッション更新を監視
        client.onSessionUpdated = { [weak self] session in
            Task { @MainActor in
                self?.isLoggedIn = session != nil
            }
        }
    }

    // MARK: - Actions

    /// ログイン
    func login(identifier: String, password: String) async {
        guard !identifier.isEmpty, !password.isEmpty else {
            errorMessage = "ハンドルとパスワードを入力してください"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            _ = try await authService.login(identifier: identifier, password: password)
            isLoggedIn = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// ログアウト
    func logout() async {
        await authService.logout()
        isLoggedIn = false
    }
}
