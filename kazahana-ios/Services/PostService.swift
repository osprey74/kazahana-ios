// PostService.swift
// kazahana-ios
// 投稿・インタラクション操作サービス

import Foundation

final class PostService {

    private let client: ATProtoClient

    init(client: ATProtoClient) {
        self.client = client
    }

    // MARK: - 投稿作成

    func createPost(text: String, facets: [Facet]? = nil, replyTo: ReplyTarget? = nil, quotePost: PostView? = nil) async throws -> CreateRecordResponse {
        guard let did = client.currentSession?.did else { throw ATProtoError.unauthorized }

        var replyRef: PostReplyRef? = nil
        if let replyTo {
            replyRef = PostReplyRef(
                root: PostRefStrong(uri: replyTo.rootUri, cid: replyTo.rootCid),
                parent: PostRefStrong(uri: replyTo.parentUri, cid: replyTo.parentCid)
            )
        }

        var quoteEmbed: QuoteEmbedRecord? = nil
        if let quotePost {
            quoteEmbed = QuoteEmbedRecord(uri: quotePost.uri, cid: quotePost.cid)
        }

        let record = PostRecordCreate(text: text, facets: facets, replyRef: replyRef, quoteEmbed: quoteEmbed)
        let body = CreateRecordRequest(repo: did, collection: "app.bsky.feed.post", record: record)
        return try await client.post(nsid: "com.atproto.repo.createRecord", body: body)
    }

    // MARK: - 投稿削除

    func deletePost(uri: String) async throws {
        guard let did = client.currentSession?.did else { throw ATProtoError.unauthorized }
        let rkey = uri.components(separatedBy: "/").last ?? ""
        let body = DeleteRecordRequest(repo: did, collection: "app.bsky.feed.post", rkey: rkey)
        let _: EmptyResponse = try await client.post(nsid: "com.atproto.repo.deleteRecord", body: body)
    }

    // MARK: - いいね

    func like(uri: String, cid: String) async throws -> CreateRecordResponse {
        guard let did = client.currentSession?.did else { throw ATProtoError.unauthorized }
        let record = LikeRecord(subject: StrongRef(uri: uri, cid: cid))
        let body = CreateRecordRequest(repo: did, collection: "app.bsky.feed.like", record: record)
        return try await client.post(nsid: "com.atproto.repo.createRecord", body: body)
    }

    func unlike(likeUri: String) async throws {
        guard let did = client.currentSession?.did else { throw ATProtoError.unauthorized }
        let rkey = likeUri.components(separatedBy: "/").last ?? ""
        let body = DeleteRecordRequest(repo: did, collection: "app.bsky.feed.like", rkey: rkey)
        let _: EmptyResponse = try await client.post(nsid: "com.atproto.repo.deleteRecord", body: body)
    }

    // MARK: - リポスト

    func repost(uri: String, cid: String) async throws -> CreateRecordResponse {
        guard let did = client.currentSession?.did else { throw ATProtoError.unauthorized }
        let record = RepostRecord(subject: StrongRef(uri: uri, cid: cid))
        let body = CreateRecordRequest(repo: did, collection: "app.bsky.feed.repost", record: record)
        return try await client.post(nsid: "com.atproto.repo.createRecord", body: body)
    }

    func unrepost(repostUri: String) async throws {
        guard let did = client.currentSession?.did else { throw ATProtoError.unauthorized }
        let rkey = repostUri.components(separatedBy: "/").last ?? ""
        let body = DeleteRecordRequest(repo: did, collection: "app.bsky.feed.repost", rkey: rkey)
        let _: EmptyResponse = try await client.post(nsid: "com.atproto.repo.deleteRecord", body: body)
    }

    // MARK: - スレッド取得

    func getThread(uri: String, depth: Int = 6) async throws -> ThreadResponse {
        return try await client.get(
            nsid: "app.bsky.feed.getPostThread",
            params: ["uri": uri, "depth": "\(depth)"]
        )
    }

    // MARK: - いいね / リポストユーザー一覧

    func getLikes(uri: String, limit: Int = 50, cursor: String? = nil) async throws -> LikesResponse {
        var params: [String: String] = ["uri": uri, "limit": "\(limit)"]
        if let cursor = cursor { params["cursor"] = cursor }
        return try await client.get(nsid: "app.bsky.feed.getLikes", params: params)
    }

    func getRepostedBy(uri: String, limit: Int = 50, cursor: String? = nil) async throws -> RepostedByResponse {
        var params: [String: String] = ["uri": uri, "limit": "\(limit)"]
        if let cursor = cursor { params["cursor"] = cursor }
        return try await client.get(nsid: "app.bsky.feed.getRepostedBy", params: params)
    }

    // MARK: - レコード取得

    func getRecord(repo: String, collection: String, rkey: String) async throws -> GetRecordResponse {
        return try await client.getRecord(repo: repo, collection: collection, rkey: rkey)
    }

    // MARK: - 複数投稿取得（通知のsubjectなど）

    func getPosts(uris: [String]) async throws -> [PostView] {
        guard !uris.isEmpty else { return [] }
        let queryItems = uris.map { URLQueryItem(name: "uris", value: $0) }
        let response: GetPostsResponse = try await client.getWithArrayParams(
            nsid: "app.bsky.feed.getPosts",
            queryItems: queryItems
        )
        return response.posts
    }
}

// MARK: - リクエスト/レスポンス型

struct CreateRecordRequest<R: Encodable>: Encodable {
    let repo: String
    let collection: String
    let record: R
}

struct DeleteRecordRequest: Encodable {
    let repo: String
    let collection: String
    let rkey: String
}

struct CreateRecordResponse: Codable {
    let uri: String
    let cid: String
}

struct EmptyResponse: Codable {}

struct StrongRef: Codable {
    let uri: String
    let cid: String
}

struct LikeRecord: Encodable {
    let type = "app.bsky.feed.like"
    let subject: StrongRef
    let createdAt: String = ISO8601DateFormatter().string(from: Date())
    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case subject, createdAt
    }
}

struct RepostRecord: Encodable {
    let type = "app.bsky.feed.repost"
    let subject: StrongRef
    let createdAt: String = ISO8601DateFormatter().string(from: Date())
    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case subject, createdAt
    }
}

// MARK: - リプライ用

struct ReplyTarget {
    let rootUri: String
    let rootCid: String
    let parentUri: String
    let parentCid: String
}

struct PostReplyRef: Codable {
    let root: PostRefStrong
    let parent: PostRefStrong
}

struct PostRefStrong: Codable {
    let uri: String
    let cid: String
}

// MARK: - いいね/リポストユーザー一覧レスポンス

struct LikesResponse: Codable {
    let uri: String
    let likes: [LikeView]
    let cursor: String?
}

struct LikeView: Codable {
    let actor: ProfileViewBasic
    let createdAt: String
}

struct RepostedByResponse: Codable {
    let uri: String
    let repostedBy: [ProfileViewBasic]
    let cursor: String?
}

// MARK: - スレッドレスポンス

struct ThreadResponse: Codable {
    let thread: ThreadViewPost
}

final class ThreadViewPost: Codable {
    let type: String
    let post: PostView?
    let parent: ThreadViewPost?
    let replies: [ThreadViewPost]?

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case post, parent, replies
    }
}
