// ChatService.swift
// kazahana-ios
// chat.bsky.convo.* API サービス層

import Foundation

/// DM チャット API の呼び出しを担うサービス
final class ChatService {

    private let client: ATProtoClient

    init(client: ATProtoClient) {
        self.client = client
    }

    // MARK: - 会話一覧

    /// 会話一覧を取得する
    /// - Parameters:
    ///   - cursor: ページネーション用カーソル
    ///   - limit: 取得件数（最大100）
    func listConvos(cursor: String? = nil, limit: Int = 20) async throws -> ListConvosResponse {
        var params: [String: String] = ["limit": "\(limit)"]
        if let cursor { params["cursor"] = cursor }
        return try await client.getWithProxy(
            nsid: "chat.bsky.convo.listConvos",
            params: params
        )
    }

    /// 特定の会話を取得する
    func getConvo(convoId: String) async throws -> ConvoView {
        let response: GetConvoResponse = try await client.getWithProxy(
            nsid: "chat.bsky.convo.getConvo",
            params: ["convoId": convoId]
        )
        return response.convo
    }

    // MARK: - メッセージ

    /// メッセージ一覧を取得する（新しい順）
    func getMessages(convoId: String, cursor: String? = nil, limit: Int = 50) async throws -> GetMessagesResponse {
        var params: [String: String] = ["convoId": convoId, "limit": "\(limit)"]
        if let cursor { params["cursor"] = cursor }
        return try await client.getWithProxy(
            nsid: "chat.bsky.convo.getMessages",
            params: params
        )
    }

    /// メッセージを送信する
    func sendMessage(convoId: String, text: String, facets: [Facet]? = nil) async throws -> SendMessageResponse {
        let body = SendMessageBody(
            convoId: convoId,
            message: SendMessageBody.MessageInput(text: text, facets: facets)
        )
        return try await client.postWithProxy(
            nsid: "chat.bsky.convo.sendMessage",
            body: body
        )
    }

    /// 自分のメッセージを削除する
    func deleteMessageForSelf(convoId: String, messageId: String) async throws -> DeleteMessageForSelfResponse {
        let body = DeleteMessageBody(convoId: convoId, messageId: messageId)
        return try await client.postWithProxy(
            nsid: "chat.bsky.convo.deleteMessageForSelf",
            body: body
        )
    }

    // MARK: - 既読処理

    /// 会話を既読にする
    func updateRead(convoId: String, messageId: String? = nil) async throws {
        let body = UpdateReadBody(convoId: convoId, messageId: messageId)
        let _: ConvoView = try await client.postWithProxy(
            nsid: "chat.bsky.convo.updateRead",
            body: body
        )
    }

    // MARK: - 新規会話

    /// メンバーを指定して会話を取得または作成する
    func getConvoForMembers(memberDIDs: [String]) async throws -> ConvoView {
        let items = memberDIDs.map { URLQueryItem(name: "members", value: $0) }
        let response: GetConvoForMembersResponse = try await client.getWithProxyArrayParams(
            nsid: "chat.bsky.convo.getConvoForMembers",
            queryItems: items
        )
        return response.convo
    }

    // MARK: - ミュート・退出

    /// 会話をミュートする
    func muteConvo(convoId: String) async throws -> ConvoView {
        let body = MuteConvoBody(convoId: convoId)
        let response: MuteConvoResponse = try await client.postWithProxy(
            nsid: "chat.bsky.convo.muteConvo",
            body: body
        )
        return response.convo
    }

    /// 会話のミュートを解除する
    func unmuteConvo(convoId: String) async throws -> ConvoView {
        let body = UnmuteConvoBody(convoId: convoId)
        let response: UnmuteConvoResponse = try await client.postWithProxy(
            nsid: "chat.bsky.convo.unmuteConvo",
            body: body
        )
        return response.convo
    }

    /// 会話から退出する
    func leaveConvo(convoId: String) async throws {
        let body = LeaveConvoBody(convoId: convoId)
        let _: LeaveConvoResponse = try await client.postWithProxy(
            nsid: "chat.bsky.convo.leaveConvo",
            body: body
        )
    }

    // MARK: - メッセージリクエスト承認

    /// 会話のメッセージリクエストを承認する
    func acceptConvo(convoId: String) async throws {
        let body = AcceptConvoBody(convoId: convoId)
        let _: AcceptConvoResponse = try await client.postWithProxy(
            nsid: "chat.bsky.convo.acceptConvo",
            body: body
        )
    }

    // MARK: - リアクション

    /// メッセージにリアクション（絵文字）を追加する
    /// - Parameters:
    ///   - convoId: 会話 ID
    ///   - messageId: メッセージ ID
    ///   - value: 絵文字文字列（例: "❤️"）
    func addReaction(convoId: String, messageId: String, value: String) async throws -> AddReactionResponse {
        let body = AddReactionBody(convoId: convoId, messageId: messageId, value: value)
        return try await client.postWithProxy(
            nsid: "chat.bsky.convo.addReaction",
            body: body
        )
    }

    /// メッセージのリアクションを削除する
    /// - Parameters:
    ///   - convoId: 会話 ID
    ///   - messageId: メッセージ ID
    ///   - value: 削除する絵文字文字列
    func removeReaction(convoId: String, messageId: String, value: String) async throws -> RemoveReactionResponse {
        let body = RemoveReactionBody(convoId: convoId, messageId: messageId, value: value)
        return try await client.postWithProxy(
            nsid: "chat.bsky.convo.removeReaction",
            body: body
        )
    }

    // MARK: - 未読数

    /// 全未読メッセージ数を取得する
    func getUnreadCount() async throws -> Int {
        let response: GetUnreadCountResponse = try await client.getWithProxy(
            nsid: "chat.bsky.convo.getUnreadCount"
        )
        return response.count
    }

    // MARK: - メッセージリクエスト（グループ招待含む）

    /// 会話リクエスト一覧を取得する（incoming + outgoing）
    func listConvoRequests(cursor: String? = nil, limit: Int = 20) async throws -> ListConvoRequestsResponse {
        var params: [String: String] = ["limit": "\(limit)"]
        if let cursor { params["cursor"] = cursor }
        return try await client.getWithProxy(
            nsid: "chat.bsky.convo.listConvoRequests",
            params: params
        )
    }

    // MARK: - グループ参加（Phase 2）

    /// 招待リンクのプレビューを取得する
    func getJoinLinkPreviews(codes: [String]) async throws -> GetJoinLinkPreviewsResponse {
        let items = codes.map { URLQueryItem(name: "codes", value: $0) }
        return try await client.getWithProxyArrayParams(
            nsid: "chat.bsky.group.getJoinLinkPreviews",
            queryItems: items
        )
    }

    /// 招待コードでグループへ参加申請する
    func requestJoin(code: String) async throws -> RequestJoinResponse {
        let body = RequestJoinBody(code: code)
        return try await client.postWithProxy(
            nsid: "chat.bsky.group.requestJoin",
            body: body
        )
    }

    /// 保留中の参加申請を取り下げる
    func withdrawJoinRequest(convoId: String) async throws {
        let body = WithdrawJoinRequestBody(convoId: convoId)
        let _: WithdrawJoinRequestResponse = try await client.postWithProxy(
            nsid: "chat.bsky.group.withdrawJoinRequest",
            body: body
        )
    }

    // MARK: - グループロック

    /// グループ会話をロックする（投稿停止）
    func lockConvo(convoId: String) async throws -> ConvoView {
        let body = LockConvoBody(convoId: convoId)
        let response: LockConvoResponse = try await client.postWithProxy(
            nsid: "chat.bsky.convo.lockConvo",
            body: body
        )
        return response.convo
    }

    /// グループ会話のロックを解除する
    func unlockConvo(convoId: String) async throws -> ConvoView {
        let body = UnlockConvoBody(convoId: convoId)
        let response: UnlockConvoResponse = try await client.postWithProxy(
            nsid: "chat.bsky.convo.unlockConvo",
            body: body
        )
        return response.convo
    }
}
