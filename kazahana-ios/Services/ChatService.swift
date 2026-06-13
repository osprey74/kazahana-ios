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

    // MARK: - チャットプライバシー設定（Phase 4）

    /// chat.bsky.actor.declaration を取得する
    func getChatDeclaration() async throws -> ChatDeclaration {
        guard let did = client.currentSession?.did else { throw ChatServiceError.notLoggedIn }
        struct RecordResponse: Decodable {
            let value: ChatDeclaration?
        }
        do {
            let response: RecordResponse = try await client.get(
                nsid: "com.atproto.repo.getRecord",
                params: ["repo": did, "collection": "chat.bsky.actor.declaration", "rkey": "self"]
            )
            return response.value ?? ChatDeclaration()
        } catch {
            // レコードが存在しない場合はデフォルト値
            return ChatDeclaration()
        }
    }

    /// chat.bsky.actor.declaration を更新する
    func updateChatDeclaration(_ declaration: ChatDeclaration) async throws {
        guard let did = client.currentSession?.did else { throw ChatServiceError.notLoggedIn }
        try await client.putRecord(
            repo: did,
            collection: "chat.bsky.actor.declaration",
            rkey: "self",
            record: declaration
        )
    }

    /// 相手と共通のグループ一覧を取得する
    func listMutualGroups(did: String) async throws -> ListMutualGroupsResponse {
        return try await client.getWithProxy(
            nsid: "chat.bsky.group.listMutualGroups",
            params: ["did": did]
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

    // MARK: - グループ作成・管理（Phase 3）

    /// グループを作成する
    func createGroup(name: String, memberDIDs: [String]) async throws -> ConvoView {
        let body = CreateGroupBody(name: name, members: memberDIDs)
        let response: CreateGroupResponse = try await client.postWithProxy(
            nsid: "chat.bsky.group.createGroup",
            body: body
        )
        return response.convo
    }

    /// グループ名を編集する
    func editGroup(convoId: String, name: String) async throws -> ConvoView {
        let body = EditGroupBody(convoId: convoId, name: name)
        let response: EditGroupResponse = try await client.postWithProxy(
            nsid: "chat.bsky.group.editGroup",
            body: body
        )
        return response.convo
    }

    /// メンバーを追加する
    func addMembers(convoId: String, memberDIDs: [String]) async throws -> ConvoView {
        let body = AddMembersBody(convoId: convoId, members: memberDIDs)
        let response: AddMembersResponse = try await client.postWithProxy(
            nsid: "chat.bsky.group.addMembers",
            body: body
        )
        return response.convo
    }

    /// メンバーを削除する（kick）
    func removeMembers(convoId: String, memberDIDs: [String]) async throws -> ConvoView {
        let body = RemoveMembersBody(convoId: convoId, members: memberDIDs)
        let response: RemoveMembersResponse = try await client.postWithProxy(
            nsid: "chat.bsky.group.removeMembers",
            body: body
        )
        return response.convo
    }

    /// 招待リンクを作成する
    func createJoinLink(convoId: String, joinRule: String = "anyone", requireApproval: Bool? = nil) async throws -> ConvoView {
        let body = CreateJoinLinkBody(convoId: convoId, joinRule: joinRule, requireApproval: requireApproval)
        let _: GroupOperationResponse = try await client.postWithProxy(
            nsid: "chat.bsky.group.createJoinLink",
            body: body
        )
        return try await getConvo(convoId: convoId)
    }

    /// 招待リンクの設定を変更する
    func editJoinLink(convoId: String, joinRule: String? = nil, requireApproval: Bool? = nil) async throws -> ConvoView {
        let body = EditJoinLinkBody(convoId: convoId, joinRule: joinRule, requireApproval: requireApproval)
        let _: GroupOperationResponse = try await client.postWithProxy(
            nsid: "chat.bsky.group.editJoinLink",
            body: body
        )
        return try await getConvo(convoId: convoId)
    }

    /// 招待リンクを有効化する
    func enableJoinLink(convoId: String) async throws -> ConvoView {
        let body = EnableJoinLinkBody(convoId: convoId)
        let _: GroupOperationResponse = try await client.postWithProxy(
            nsid: "chat.bsky.group.enableJoinLink",
            body: body
        )
        return try await getConvo(convoId: convoId)
    }

    /// 招待リンクを無効化する
    func disableJoinLink(convoId: String) async throws -> ConvoView {
        let body = DisableJoinLinkBody(convoId: convoId)
        let _: GroupOperationResponse = try await client.postWithProxy(
            nsid: "chat.bsky.group.disableJoinLink",
            body: body
        )
        return try await getConvo(convoId: convoId)
    }

    /// 参加申請一覧を取得する（owner 用）
    func listJoinRequests(convoId: String, cursor: String? = nil, limit: Int = 20) async throws -> ListJoinRequestsResponse {
        var params: [String: String] = ["convoId": convoId, "limit": "\(limit)"]
        if let cursor { params["cursor"] = cursor }
        return try await client.getWithProxy(
            nsid: "chat.bsky.group.listJoinRequests",
            params: params
        )
    }

    /// 参加申請を承認する
    func approveJoinRequest(convoId: String, member: String) async throws {
        let body = ApproveJoinRequestBody(convoId: convoId, member: member)
        let _: GroupOperationResponse = try await client.postWithProxy(
            nsid: "chat.bsky.group.approveJoinRequest",
            body: body
        )
    }

    /// 参加申請を拒否する
    func rejectJoinRequest(convoId: String, member: String) async throws {
        let body = RejectJoinRequestBody(convoId: convoId, member: member)
        let _: GroupOperationResponse = try await client.postWithProxy(
            nsid: "chat.bsky.group.rejectJoinRequest",
            body: body
        )
    }

    /// 参加申請を既読にする
    func updateJoinRequestsRead(convoId: String) async throws {
        let body = UpdateJoinRequestsReadBody(convoId: convoId)
        struct EmptyResponse: Decodable {}
        let _: EmptyResponse = try await client.postWithProxy(
            nsid: "chat.bsky.group.updateJoinRequestsRead",
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
