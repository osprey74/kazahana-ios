// GraphService.swift
// kazahana-ios
// フォロー/フォロー解除、ブロック等のグラフ操作サービス

import Foundation

struct GraphService {
    private let client: ATProtoClient

    init(client: ATProtoClient) {
        self.client = client
    }

    // MARK: - フォロー

    /// ユーザーをフォローする
    /// - Returns: 作成されたフォローレコードの URI と CID
    func follow(did: String) async throws -> StrongRef {
        guard let session = client.currentSession else {
            throw ATProtoError.unauthorized
        }

        let record = FollowRecord(subject: did, createdAt: ISO8601DateFormatter().string(from: Date()))
        let request = CreateRecordRequest(
            repo: session.did,
            collection: "app.bsky.graph.follow",
            record: record
        )
        let response: CreateRecordResponse = try await client.post(
            nsid: "com.atproto.repo.createRecord",
            body: request
        )
        return StrongRef(uri: response.uri, cid: response.cid)
    }

    /// フォローを解除する
    /// - Parameter followUri: フォローレコードの URI (viewer.following の値)
    func unfollow(followUri: String) async throws {
        guard let session = client.currentSession else {
            throw ATProtoError.unauthorized
        }

        let parts = followUri.components(separatedBy: "/")
        guard parts.count >= 5 else {
            throw ATProtoError.invalidResponse
        }
        let rkey = parts[parts.count - 1]

        let request = DeleteRecordRequest(
            repo: session.did,
            collection: "app.bsky.graph.follow",
            rkey: rkey
        )
        let _: EmptyResponse = try await client.post(nsid: "com.atproto.repo.deleteRecord", body: request)
    }

    // MARK: - プロフィール取得

    /// アクターのプロフィールを取得する
    func getProfile(actor: String) async throws -> ProfileView {
        try await client.get(nsid: "app.bsky.actor.getProfile", params: ["actor": actor])
    }

    /// アクターの投稿一覧を取得する
    /// - Parameter filter: "posts_no_replies"（投稿のみ）/ "posts_with_replies"（返信含む）/ "posts_with_media"（メディアのみ）
    func getAuthorFeed(actor: String, limit: Int = 30, cursor: String? = nil, filter: String? = nil) async throws -> TimelineResponse {
        var params: [String: String] = ["actor": actor, "limit": "\(limit)"]
        if let cursor = cursor { params["cursor"] = cursor }
        if let filter = filter { params["filter"] = filter }
        return try await client.get(nsid: "app.bsky.feed.getAuthorFeed", params: params)
    }

    /// アクターのいいね一覧を取得する
    func getActorLikes(actor: String, limit: Int = 30, cursor: String? = nil) async throws -> TimelineResponse {
        var params: [String: String] = ["actor": actor, "limit": "\(limit)"]
        if let cursor = cursor { params["cursor"] = cursor }
        return try await client.get(nsid: "app.bsky.feed.getActorLikes", params: params)
    }

    /// フォロワー一覧を取得する
    func getFollowers(actor: String, limit: Int = 50, cursor: String? = nil) async throws -> FollowersResponse {
        var params: [String: String] = ["actor": actor, "limit": "\(limit)"]
        if let cursor = cursor { params["cursor"] = cursor }
        return try await client.get(nsid: "app.bsky.graph.getFollowers", params: params)
    }

    /// フォロー中一覧を取得する
    func getFollows(actor: String, limit: Int = 50, cursor: String? = nil) async throws -> FollowsResponse {
        var params: [String: String] = ["actor": actor, "limit": "\(limit)"]
        if let cursor = cursor { params["cursor"] = cursor }
        return try await client.get(nsid: "app.bsky.graph.getFollows", params: params)
    }

    // MARK: - ミュート

    /// ユーザーをミュートする
    func muteActor(did: String) async throws {
        struct MuteRequest: Encodable { let actor: String }
        let _: EmptyResponse = try await client.post(nsid: "app.bsky.graph.muteActor", body: MuteRequest(actor: did))
    }

    /// ユーザーのミュートを解除する
    func unmuteActor(did: String) async throws {
        struct UnmuteRequest: Encodable { let actor: String }
        let _: EmptyResponse = try await client.post(nsid: "app.bsky.graph.unmuteActor", body: UnmuteRequest(actor: did))
    }

    // MARK: - ブロック

    /// ユーザーをブロックする
    /// - Returns: 作成されたブロックレコードの URI
    func blockActor(did: String) async throws -> String {
        guard let session = client.currentSession else {
            throw ATProtoError.unauthorized
        }
        let record = BlockRecord(subject: did, createdAt: ISO8601DateFormatter().string(from: Date()))
        let request = CreateRecordRequest(
            repo: session.did,
            collection: "app.bsky.graph.block",
            record: record
        )
        let response: CreateRecordResponse = try await client.post(
            nsid: "com.atproto.repo.createRecord",
            body: request
        )
        return response.uri
    }

    /// ブロックを解除する
    /// - Parameter blockUri: ブロックレコードの URI (viewer.blocking の値)
    func unblockActor(blockUri: String) async throws {
        guard let session = client.currentSession else {
            throw ATProtoError.unauthorized
        }
        let parts = blockUri.components(separatedBy: "/")
        guard parts.count >= 5 else {
            throw ATProtoError.invalidResponse
        }
        let rkey = parts[parts.count - 1]
        let request = DeleteRecordRequest(
            repo: session.did,
            collection: "app.bsky.graph.block",
            rkey: rkey
        )
        let _: EmptyResponse = try await client.post(nsid: "com.atproto.repo.deleteRecord", body: request)
    }

    // MARK: - リスト管理

    /// 自分のリスト一覧を取得する
    func getMyLists(limit: Int = 100) async throws -> [GraphListView] {
        guard let session = client.currentSession else {
            throw ATProtoError.unauthorized
        }
        let response: GetListsResponse = try await client.get(
            nsid: "app.bsky.graph.getLists",
            params: ["actor": session.did, "limit": "\(limit)"]
        )
        return response.lists
    }

    /// ユーザーがどのリストのメンバーかを取得する（subject DID のリストitem URI 辞書）
    /// - Returns: [listUri: listitemUri]
    func getListMemberships(targetDid: String) async throws -> [String: String] {
        guard let session = client.currentSession else {
            throw ATProtoError.unauthorized
        }
        var result: [String: String] = [:]
        var cursor: String? = nil
        repeat {
            var params: [String: String] = [
                "repo": session.did,
                "collection": "app.bsky.graph.listitem",
                "limit": "100"
            ]
            if let c = cursor { params["cursor"] = c }
            let response: ListRecordsResponse<ListItemRecord> = try await client.get(
                nsid: "com.atproto.repo.listRecords",
                params: params
            )
            for record in response.records where record.value.subject == targetDid {
                result[record.value.list] = record.uri
            }
            cursor = response.cursor
        } while cursor != nil
        return result
    }

    /// ユーザーをリストに追加する
    /// - Returns: 作成された listitem レコードの URI
    func addToList(targetDid: String, listUri: String) async throws -> String {
        guard let session = client.currentSession else {
            throw ATProtoError.unauthorized
        }
        let record = ListItemRecord(
            list: listUri,
            subject: targetDid,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        let request = CreateRecordRequest(
            repo: session.did,
            collection: "app.bsky.graph.listitem",
            record: record
        )
        let response: CreateRecordResponse = try await client.post(
            nsid: "com.atproto.repo.createRecord",
            body: request
        )
        return response.uri
    }

    /// ユーザーをリストから削除する
    /// - Parameter listitemUri: listitem レコードの URI
    func removeFromList(listitemUri: String) async throws {
        guard let session = client.currentSession else {
            throw ATProtoError.unauthorized
        }
        let parts = listitemUri.components(separatedBy: "/")
        guard parts.count >= 5 else {
            throw ATProtoError.invalidResponse
        }
        let rkey = parts[parts.count - 1]
        let request = DeleteRecordRequest(
            repo: session.did,
            collection: "app.bsky.graph.listitem",
            rkey: rkey
        )
        let _: EmptyResponse = try await client.post(nsid: "com.atproto.repo.deleteRecord", body: request)
    }

    // MARK: - ユーザープリファレンス

    /// Bluesky のユーザープリファレンスから投稿言語設定を取得する
    func getPostLanguages() async throws -> [String] {
        let response: PreferencesResponse = try await client.get(nsid: "app.bsky.actor.getPreferences", params: [:])
        for pref in response.preferences {
            if pref.type == "app.bsky.actor.defs#languagesPref", let langs = pref.postLanguages, !langs.isEmpty {
                return langs
            }
        }
        return []
    }
}

// MARK: - フォロワー/フォロー一覧レスポンス

struct FollowersResponse: Codable {
    let subject: ProfileViewBasic
    let followers: [ProfileViewBasic]
    let cursor: String?
}

struct FollowsResponse: Codable {
    let subject: ProfileViewBasic
    let follows: [ProfileViewBasic]
    let cursor: String?
}

// MARK: - フォローレコード

private struct FollowRecord: Encodable {
    let type = "app.bsky.graph.follow"
    let subject: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case subject
        case createdAt
    }
}

private struct BlockRecord: Encodable {
    let type = "app.bsky.graph.block"
    let subject: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case subject
        case createdAt
    }
}

struct ListItemRecord: Codable {
    let list: String
    let subject: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case list
        case subject
        case createdAt
    }
}

// com.atproto.repo.listRecords のレスポンス
struct ListRecordsResponse<V: Codable>: Codable {
    struct Record: Codable {
        let uri: String
        let cid: String
        let value: V
    }
    let records: [Record]
    let cursor: String?
}


