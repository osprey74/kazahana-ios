// ChatThreadViewModel.swift
// kazahana-ios
// メッセージスレッドの状態管理（15秒ポーリング）

import Foundation
import Observation

@Observable
final class ChatThreadViewModel {
    var messages: [ChatMessageViewOrDeleted] = []
    var isLoading = false
    var isSending = false
    var errorMessage: String?
    var sendError: String?

    private var cursor: String?
    private var hasMore = true
    private let chatService: ChatService
    private let convoId: String
    private var pollingTask: Task<Void, Never>?

    init(chatService: ChatService, convoId: String) {
        self.chatService = chatService
        self.convoId = convoId
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
            let response = try await chatService.getMessages(convoId: convoId, limit: 50)
            // API は新しい順で返す → 表示は古い順にするため反転
            messages = response.messages.reversed()
            cursor = response.cursor
            hasMore = response.cursor != nil
            await markRead()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    func loadMore() async {
        guard hasMore, !isLoading, let cursor else { return }
        isLoading = true

        do {
            let response = try await chatService.getMessages(convoId: convoId, cursor: cursor, limit: 50)
            // 古いメッセージを先頭に挿入
            messages.insert(contentsOf: response.messages.reversed(), at: 0)
            self.cursor = response.cursor
            hasMore = response.cursor != nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - 送信

    @MainActor
    func sendMessage(text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isSending else { return }
        isSending = true
        sendError = nil

        do {
            let response = try await chatService.sendMessage(convoId: convoId, text: text)
            // レスポンスを ChatMessageView に変換してリストに追加
            let newMessage = ChatMessageView(
                id: response.id,
                rev: response.rev,
                text: response.text,
                sender: response.sender,
                sentAt: response.sentAt,
                facets: response.facets
            )
            messages.append(.message(newMessage))
        } catch {
            sendError = error.localizedDescription
        }
        isSending = false
    }

    // MARK: - 削除

    @MainActor
    func deleteMessage(messageId: String) async {
        do {
            let deleted = try await chatService.deleteMessageForSelf(convoId: convoId, messageId: messageId)
            // 削除済みに置換
            if let idx = messages.firstIndex(where: {
                switch $0 {
                case .message(let m): return m.id == messageId
                case .deleted(let d): return d.id == messageId
                }
            }) {
                let deletedView = DeletedMessageView(
                    id: deleted.id,
                    rev: deleted.rev,
                    sender: deleted.sender,
                    sentAt: deleted.sentAt
                )
                messages[idx] = .deleted(deletedView)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 既読

    @MainActor
    func markRead() async {
        do {
            try await chatService.updateRead(convoId: convoId)
        } catch {
            // 既読処理失敗は無視
        }
    }

    // MARK: - ポーリング

    func startPolling() {
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { break }
                await self?.pollNewMessages()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    @MainActor
    private func pollNewMessages() async {
        guard !isLoading else { return }
        do {
            // cursor なしで最新メッセージを取得
            let response = try await chatService.getMessages(convoId: convoId, limit: 50)
            let newMessages = response.messages.reversed() as [ChatMessageViewOrDeleted]
            // 新しいメッセージのみ末尾に追加
            let existingIDs = Set(messages.compactMap { msg -> String? in
                switch msg {
                case .message(let m): return m.id
                case .deleted(let d): return d.id
                }
            })
            let toAdd = newMessages.filter { msg -> Bool in
                switch msg {
                case .message(let m): return !existingIDs.contains(m.id)
                case .deleted(let d): return !existingIDs.contains(d.id)
                }
            }
            if !toAdd.isEmpty {
                messages.append(contentsOf: toAdd)
                await markRead()
            }
        } catch {
            // ポーリングエラーは無視
        }
    }
}
