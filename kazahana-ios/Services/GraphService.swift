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
