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
    func sendMessage(text: String, replyToMessageId: String? = nil) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isSending else { return }
        isSending = true
        sendError = nil

        do {
            // URL・ハッシュタグの facets を自動生成（DID 未解決のメンションは除外）
            let detected = RichTextParser.detectFacets(in: text)
            let facets = RichTextParser.buildFacets(from: detected.filter {
                if case .mention = $0.kind { return false }
                return true
            })
            let response = try await chatService.sendMessage(
                convoId: convoId, text: text,
                facets: facets.isEmpty ? nil : facets,
                replyToMessageId: replyToMessageId
            )
            // レスポンスを ChatMessageView に変換してリストに追加
            let newMessage = ChatMessageView(
                id: response.id,
                rev: response.rev,
                text: response.text,
                sender: response.sender,
                sentAt: response.sentAt,
                facets: response.facets,
                reactions: response.reactions,
                embed: nil
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
                case .system(let s): return s.id == messageId
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

    // MARK: - リアクション

    @MainActor
    func toggleReaction(messageId: String, emoji: String, myDID: String) async {
        // 既に自分がそのリアクションを付けているか確認
        let hasReaction = currentReactions(messageId: messageId)
            .contains { $0.value == emoji && $0.sender.did == myDID }
        do {
            let response: ChatMessageView
            if hasReaction {
                let r = try await chatService.removeReaction(convoId: convoId, messageId: messageId, value: emoji)
                response = ChatMessageView(id: r.id, rev: r.rev, text: r.text, sender: r.sender, sentAt: r.sentAt, facets: r.facets, reactions: r.reactions, embed: nil)
            } else {
                let r = try await chatService.addReaction(convoId: convoId, messageId: messageId, value: emoji)
                response = ChatMessageView(id: r.id, rev: r.rev, text: r.text, sender: r.sender, sentAt: r.sentAt, facets: r.facets, reactions: r.reactions, embed: nil)
            }
            // メッセージリストを更新
            if let idx = messages.firstIndex(where: {
                if case .message(let m) = $0 { return m.id == messageId }
                return false
            }) {
                messages[idx] = .message(response)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 指定メッセージの現在のリアクション一覧を返す
    func currentReactions(messageId: String) -> [ChatReaction] {
        for msg in messages {
            if case .message(let m) = msg, m.id == messageId {
                return m.reactions ?? []
            }
        }
        return []
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
                case .system(let s): return s.id
                }
            })
            let toAdd = newMessages.filter { msg -> Bool in
                switch msg {
                case .message(let m): return !existingIDs.contains(m.id)
                case .deleted(let d): return !existingIDs.contains(d.id)
                case .system(let s): return !existingIDs.contains(s.id)
                }
            }
            // リアクション変化を反映（既存メッセージを更新）
            for newMsg in newMessages {
                if case .message(let newM) = newMsg,
                   let idx = messages.firstIndex(where: {
                       if case .message(let m) = $0 { return m.id == newM.id }
                       return false
                   }) {
                    if case .message(let existing) = messages[idx] {
                        let existingReactionCount = existing.reactions?.count ?? 0
                        let newReactionCount = newM.reactions?.count ?? 0
                        if existingReactionCount != newReactionCount {
                            messages[idx] = .message(newM)
                        }
                    }
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
