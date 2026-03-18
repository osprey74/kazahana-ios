// SearchService.swift
// kazahana-ios
// 検索サービス（アクター検索・ポスト検索）

import Foundation

struct ActorSearchResponse: Codable {
    let actors: [ProfileViewBasic]
    let cursor: String?
}

struct PostSearchResponse: Codable {
    let posts: [PostView]
    let cursor: String?
    let hitsTotal: Int?
}

struct SearchService {
    private let client: ATProtoClient

    init(client: ATProtoClient) {
        self.client = client
    }

    /// アクター（ユーザー）を検索する
    func searchActors(query: String, limit: Int = 25, cursor: String? = nil) async throws -> ActorSearchResponse {
        var params: [String: String] = ["q": query, "limit": "\(limit)"]
        if let cursor = cursor { params["cursor"] = cursor }
        return try await client.get(nsid: "app.bsky.actor.searchActors", params: params)
    }

    /// ポストを検索する
    func searchPosts(query: String, limit: Int = 25, cursor: String? = nil) async throws -> PostSearchResponse {
        var params: [String: String] = ["q": query, "limit": "\(limit)"]
        if let cursor = cursor { params["cursor"] = cursor }
        return try await client.get(nsid: "app.bsky.feed.searchPosts", params: params)
    }
}
