// PostService.swift
// kazahana-ios
// 投稿・インタラクション操作サービス

import Foundation

final class PostService {

    private let client: ATProtoClient

    /// SearchService など外部サービスが同一クライアントを使用できるよう公開
    var atProtoClient: ATProtoClient { client }

    init(client: ATProtoClient) {
        self.client = client
    }

    // MARK: - 投稿作成

    func createPost(
        text: String,
        facets: [Facet]? = nil,
        replyTo: ReplyTarget? = nil,
        quotePost: PostView? = nil,
        images: [(blob: BlobRef, alt: String, aspectRatio: AspectRatioCreate?)]? = nil,
        video: (blob: BlobRef, alt: String?, aspectRatio: AspectRatioCreate?)? = nil,
        linkCard: LinkPreview? = nil,
        via: String? = nil
    ) async throws -> CreateRecordResponse {
        guard let did = client.currentSession?.did else { throw ATProtoError.unauthorized }

        var replyRef: PostReplyRef? = nil
        if let replyTo {
            replyRef = PostReplyRef(
                root: PostRefStrong(uri: replyTo.rootUri, cid: replyTo.rootCid),
                parent: PostRefStrong(uri: replyTo.parentUri, cid: replyTo.parentCid)
            )
        }

        // embed の組み立て（画像 / 動画 / 外部リンク / 引用 / 画像+引用）
        let embed: PostEmbedCreate?
        if let images, !images.isEmpty {
            let imageEmbed = ImageEmbedCreate(images: images.map { ImageEmbedItem(image: $0.blob, alt: $0.alt, aspectRatio: $0.aspectRatio) })
            if let quotePost {
                embed = .recordWithMedia(imageEmbed, QuoteEmbedRecord(uri: quotePost.uri, cid: quotePost.cid))
            } else {
                embed = .images(imageEmbed)
            }
        } else if let video {
            embed = .video(VideoEmbedCreate(video: video.blob, alt: video.alt, aspectRatio: video.aspectRatio))
        } else if let linkCard {
            let card = ExternalCardCreate(
                uri: linkCard.url.absoluteString,
                title: linkCard.title,
                description: linkCard.description,
                thumb: linkCard.thumbBlob,
                associatedRefs: linkCard.associatedRefs
            )
            embed = .external(ExternalEmbedCreate(external: card))
        } else if let quotePost {
            embed = .record(QuoteEmbedRecord(uri: quotePost.uri, cid: quotePost.cid))
        } else {
            embed = nil
        }

        let record = PostRecordCreate(text: text, facets: facets, replyRef: replyRef, embed: embed, via: via)
        let body = CreateRecordRequest(repo: did, collection: "app.bsky.feed.post", record: record)
        return try await client.post(nsid: "com.atproto.repo.createRecord", body: body)
    }

    // MARK: - 画像アップロード

    func uploadImage(data: Data, mimeType: String) async throws -> BlobRef {
        let response = try await client.uploadBlob(data: data, mimeType: mimeType)
        return response.blob
    }

    // MARK: - 動画アップロード

    /// 動画を app.bsky.video.uploadVideo 経由でアップロード
    /// 1. getServiceAuth でサービストークンを取得
    /// 2. video.bsky.app にアップロード
    /// 3. ジョブステータスをポーリングして完了まで待つ
    /// 4. 完了後の BlobRef を返す
    func uploadVideo(data: Data, mimeType: String) async throws -> BlobRef {
        guard let session = client.currentSession else { throw ATProtoError.unauthorized }

        // PDS の did:web を導出（例: https://bsky.social → did:web:bsky.social）
        let pdsHost = session.pdsHost
        let pdsDomain: String
        if let url = URL(string: pdsHost), let host = url.host {
            pdsDomain = host
        } else {
            pdsDomain = "bsky.social"
        }
        let pdsAud = "did:web:\(pdsDomain)"

        // サービス認証トークンを取得（lxm は com.atproto.repo.uploadBlob）
        let serviceToken = try await client.getServiceAuth(
            aud: pdsAud,
            lxm: "com.atproto.repo.uploadBlob",
            expSecs: 1800
        )

        // video.bsky.app にアップロード
        let ext = mimeType == "video/quicktime" ? "mov" : "mp4"
        let fileName = "\(UUID().uuidString).\(ext)"
        var jobStatus = try await client.uploadVideoToService(
            data: data,
            mimeType: mimeType,
            fileName: fileName,
            serviceToken: serviceToken
        )

        // ジョブ完了までポーリング（最大120秒、2秒間隔）
        let maxAttempts = 60
        var attempts = 0
        while jobStatus.state != "JOB_STATE_COMPLETED" && attempts < maxAttempts {
            if let error = jobStatus.error {
                throw ATProtoError.apiError(code: error, message: jobStatus.message)
            }
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2秒待機
            jobStatus = try await client.getVideoJobStatus(jobId: jobStatus.jobId, serviceToken: serviceToken)
            attempts += 1
        }

        guard jobStatus.state == "JOB_STATE_COMPLETED", let blob = jobStatus.blob else {
            throw ATProtoError.apiError(code: "VideoProcessingFailed", message: "動画の処理がタイムアウトしました")
        }

        return blob
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

    // MARK: - ブックマーク

    func bookmark(uri: String, cid: String) async throws {
        let body = BookmarkRequest(uri: uri, cid: cid)
        let _: EmptyResponse = try await client.post(nsid: "app.bsky.bookmark.createBookmark", body: body)
    }

    func unbookmark(uri: String) async throws {
        let body = UnbookmarkRequest(uri: uri)
        let _: EmptyResponse = try await client.post(nsid: "app.bsky.bookmark.deleteBookmark", body: body)
    }

    func getBookmarks(limit: Int = 50, cursor: String? = nil) async throws -> BookmarksResponse {
        var params: [String: String] = ["limit": "\(limit)"]
        if let cursor = cursor { params["cursor"] = cursor }
        return try await client.get(nsid: "app.bsky.bookmark.getBookmarks", params: params)
    }

    // MARK: - 投稿非表示

    func hidePost(uri: String) async throws {
        let body = HidePostRequest(uri: uri)
        let _: EmptyResponse = try await client.post(nsid: "app.bsky.feed.hidePost", body: body)
    }

    func unhidePost(uri: String) async throws {
        let body = HidePostRequest(uri: uri)
        let _: EmptyResponse = try await client.post(nsid: "app.bsky.feed.unhidePost", body: body)
    }

    // MARK: - スレッドミュート

    func muteThread(root: String) async throws {
        let body = MuteThreadRequest(root: root)
        let _: EmptyResponse = try await client.post(nsid: "app.bsky.graph.muteThread", body: body)
    }

    func unmuteThread(root: String) async throws {
        let body = MuteThreadRequest(root: root)
        let _: EmptyResponse = try await client.post(nsid: "app.bsky.graph.unmuteThread", body: body)
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

    func getQuotes(uri: String, limit: Int = 50, cursor: String? = nil) async throws -> QuotesResponse {
        var params: [String: String] = ["uri": uri, "limit": "\(limit)"]
        if let cursor = cursor { params["cursor"] = cursor }
        return try await client.get(nsid: "app.bsky.feed.getQuotes", params: params)
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

    // MARK: - スレッドゲート / ポストゲート

    /// スレッドゲートを作成する（投稿直後に呼ぶ）
    /// - Parameters:
    ///   - postURI: 投稿の AT-URI（createPost の戻り値 .uri）
    ///   - setting: 返信制限設定
    func createThreadgate(postURI: String, setting: ThreadgateSetting) async throws {
        guard setting != .everyone else { return } // everyone は制限なしなのでレコード不要
        guard let did = client.currentSession?.did else { throw ATProtoError.unauthorized }
        // AT-URI の末尾が rkey（投稿と同じ rkey を使う仕様）
        let rkey = postURI.components(separatedBy: "/").last ?? ""
        let record = ThreadgateCreate(
            post: postURI,
            allow: setting.rules,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        let requestWithRkey = CreateRecordRequestWithRkey(repo: did, collection: "app.bsky.feed.threadgate", rkey: rkey, record: record)
        let _: CreateRecordResponse = try await client.post(nsid: "com.atproto.repo.createRecord", body: requestWithRkey)
    }

    /// ポストゲートを作成する（引用禁止）
    func createPostgate(postURI: String, disableEmbedding: Bool) async throws {
        guard disableEmbedding else { return }
        guard let did = client.currentSession?.did else { throw ATProtoError.unauthorized }
        let rkey = postURI.components(separatedBy: "/").last ?? ""
        let record = PostgateCreate(
            post: postURI,
            embeddingRules: [PostgateEmbeddingRule()],
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        let requestWithRkey = CreateRecordRequestWithRkey(repo: did, collection: "app.bsky.feed.postgate", rkey: rkey, record: record)
        let _: CreateRecordResponse = try await client.post(nsid: "com.atproto.repo.createRecord", body: requestWithRkey)
    }

    // MARK: - 通報

    func reportPost(uri: String, cid: String, reasonType: ReportReasonType, reason: String?) async throws {
        let subject = ReportSubject(type: "com.atproto.repo.strongRef", uri: uri, cid: cid)
        let body = CreateReportRequest(reasonType: reasonType.rawValue, reason: reason, subject: subject)
        let _: CreateReportResponse = try await client.post(nsid: "com.atproto.moderation.createReport", body: body)
    }

    func reportAccount(did: String, reasonType: ReportReasonType, reason: String?) async throws {
        let subject = ReportSubject(type: "com.atproto.admin.defs#repoRef", did: did)
        let body = CreateReportRequest(reasonType: reasonType.rawValue, reason: reason, subject: subject)
        let _: CreateReportResponse = try await client.post(nsid: "com.atproto.moderation.createReport", body: body)
    }
}

// MARK: - リクエスト/レスポンス型

struct CreateRecordRequest<R: Encodable>: Encodable {
    let repo: String
    let collection: String
    let record: R
}

/// rkey 指定付き createRecord（スレッドゲート・ポストゲートは投稿と同じ rkey を使う仕様）
struct CreateRecordRequestWithRkey<R: Encodable>: Encodable {
    let repo: String
    let collection: String
    let rkey: String
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

struct QuotesResponse: Codable {
    let uri: String
    let cid: String?
    let posts: [PostView]
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
    var replies: [ThreadViewPost]?

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case post, parent, replies
    }
}

// MARK: - ブックマーク関連型

struct BookmarkRequest: Encodable {
    let uri: String
    let cid: String
}

struct UnbookmarkRequest: Encodable {
    let uri: String
}

struct BookmarksResponse: Codable {
    let bookmarks: [BookmarkView]
    let cursor: String?
}

/// app.bsky.bookmark.defs#bookmarkView
struct BookmarkView: Codable {
    /// item は postView / blockedPost / notFoundPost のユニオン型。
    /// postView の場合のみ PostView として保持し、それ以外は nil。
    let item: PostView?

    enum CodingKeys: String, CodingKey {
        case item
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // item のデコードが失敗しても nil として扱い、BookmarksResponse 全体は維持する
        item = try? container.decode(PostView.self, forKey: .item)
    }
}

// MARK: - 投稿非表示・スレッドミュート関連型

struct HidePostRequest: Encodable {
    let uri: String
}

struct MuteThreadRequest: Encodable {
    let root: String
}

// MARK: - 通報関連型

enum ReportReasonType: String, CaseIterable, Identifiable {
    case spam       = "com.atproto.moderation.defs#reasonSpam"
    case violation  = "com.atproto.moderation.defs#reasonViolation"
    case misleading = "com.atproto.moderation.defs#reasonMisleading"
    case sexual     = "com.atproto.moderation.defs#reasonSexual"
    case rude       = "com.atproto.moderation.defs#reasonRude"
    case other      = "com.atproto.moderation.defs#reasonOther"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spam:       return String(localized: "report.reason.spam")
        case .violation:  return String(localized: "report.reason.violation")
        case .misleading: return String(localized: "report.reason.misleading")
        case .sexual:     return String(localized: "report.reason.sexual")
        case .rude:       return String(localized: "report.reason.rude")
        case .other:      return String(localized: "report.reason.other")
        }
    }
}

struct ReportSubject: Encodable {
    let type: String
    let uri: String?
    let cid: String?
    let did: String?

    init(type: String, uri: String, cid: String) {
        self.type = type
        self.uri = uri
        self.cid = cid
        self.did = nil
    }

    init(type: String, did: String) {
        self.type = type
        self.did = did
        self.uri = nil
        self.cid = nil
    }

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case uri, cid, did
    }
}

struct CreateReportRequest: Encodable {
    let reasonType: String
    let reason: String?
    let subject: ReportSubject
}

struct CreateReportResponse: Codable {
    let id: Int
    let reasonType: String
}
