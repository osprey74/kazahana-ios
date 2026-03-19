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

        // 保存済みセッションがある場合、起動時にリフレッシュを試みる
        if client.currentSession != nil {
            Task {
                await refreshSessionOnLaunch()
            }
        }
    }

    /// 起動時のトークンリフレッシュ（サイレント失敗 → ログアウト）
    private func refreshSessionOnLaunch() async {
        do {
            try await client.refreshSessionPublic()
            // リフレッシュ成功後に Bluesky プリファレンスから投稿言語を取得
            await loadPostLanguages()
        } catch {
            // リフレッシュトークンも無効な場合はログアウト扱い
            await MainActor.run { isLoggedIn = false }
            client.updateSession(nil)
        }
    }

    /// Bluesky プリファレンスから投稿言語設定を取得して AppSettings に反映
    private func loadPostLanguages() async {
        let graphService = GraphService(client: client)
        if let langs = try? await graphService.getPostLanguages(), !langs.isEmpty {
            await MainActor.run {
                AppSettings.shared.postLanguages = langs
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
