// ConversationListViewModel.swift
// kazahana-ios
// 会話一覧の状態管理（30秒ポーリング）

import Foundation
import Observation

@Observable
final class ConversationListViewModel {
    var conversations: [ConvoView] = []
    var isLoading = false
    var isRefreshing = false
    var errorMessage: String?
    var unreadCount = 0

    private var cursor: String?
    private var hasMore = true
    private let chatService: ChatService
    private var pollingTask: Task<Void, Never>?

    init(chatService: ChatService) {
        self.chatService = chatService
    }

    // MARK: - 読み込み

    @MainActor
    func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        cursor = nil
        hasMore = true

        do {
            let response = try await chatService.listConvos(limit: 30)
            conversations = response.convos
            cursor = response.cursor
            hasMore = response.cursor != nil
            await refreshUnreadCount()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        cursor = nil
        hasMore = true

        do {
            let response = try await chatService.listConvos(limit: 30)
            conversations = response.convos
            cursor = response.cursor
            hasMore = response.cursor != nil
            await refreshUnreadCount()
        } catch {
            errorMessage = error.localizedDescription
        }
        isRefreshing = false
    }

    @MainActor
    func loadMore() async {
        guard hasMore, !isLoading, !isRefreshing, let cursor else { return }
        isLoading = true

        do {
            let response = try await chatService.listConvos(cursor: cursor, limit: 30)
            conversations.append(contentsOf: response.convos)
            self.cursor = response.cursor
            hasMore = response.cursor != nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - 未読数

    @MainActor
    func refreshUnreadCount() async {
        do {
            unreadCount = try await chatService.getUnreadCount()
        } catch {
            // 未読数取得失敗は無視
        }
    }

    // MARK: - ミュート・退出

    @MainActor
    func muteConvo(_ convoId: String) async {
        do {
            let updated = try await chatService.muteConvo(convoId: convoId)
            updateConvo(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func unmuteConvo(_ convoId: String) async {
        do {
            let updated = try await chatService.unmuteConvo(convoId: convoId)
            updateConvo(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func leaveConvo(_ convoId: String) async {
        do {
            try await chatService.leaveConvo(convoId: convoId)
            conversations.removeAll { $0.id == convoId }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - ポーリング

    func startPolling() {
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { break }
                await self?.silentRefresh()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    @MainActor
    private func silentRefresh() async {
        guard !isLoading, !isRefreshing else { return }
        do {
            let response = try await chatService.listConvos(limit: 30)
            conversations = response.convos
            cursor = response.cursor
            hasMore = response.cursor != nil
            unreadCount = try await chatService.getUnreadCount()
        } catch {
            // バックグラウンドポーリングエラーは無視
        }
    }

    // MARK: - Helpers

    private func updateConvo(_ updated: ConvoView) {
        if let idx = conversations.firstIndex(where: { $0.id == updated.id }) {
            conversations[idx] = updated
        }
    }
}
