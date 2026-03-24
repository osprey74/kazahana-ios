// Post.swift
// kazahana-ios
// 投稿関連モデル（AT Protocol / Bluesky）

import Foundation

// MARK: - タイムラインレスポンス

struct TimelineResponse: Codable {
    let feed: [FeedViewPost]
    let cursor: String?
}

// MARK: - FeedViewPost（タイムラインの1エントリ）

struct FeedViewPost: Codable, Identifiable, Hashable {
    static func == (lhs: FeedViewPost, rhs: FeedViewPost) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    let post: PostView
    let reply: ReplyRef?
    let reason: FeedReason?

    var id: String { post.uri }
}

// MARK: - PostView

struct PostView: Codable, Identifiable {
    var id: String { uri }
    let uri: String
    let cid: String
    let author: ProfileViewBasic
    let record: PostRecord
    let embed: PostEmbed?
    let replyCount: Int?
    let repostCount: Int?
    let likeCount: Int?
    let quoteCount: Int?
    let indexedAt: String
    let viewer: ViewerState?
    let labels: [ContentLabel]?
}

// MARK: - 投稿レコード本体

struct PostRecord: Codable {
    let text: String
    let createdAt: String?
    let langs: [String]?
    let facets: [Facet]?
    let reply: ReplyRef?
    let embed: PostEmbed?
    let via: String?
    /// BSAF タグ（例: ["bsaf:v1", "type:earthquake", "value:5+", ...]）
    let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case text, createdAt, langs, facets, reply, embed, tags
        case via = "$via"
    }
}

// MARK: - リッチテキスト Facets

struct Facet: Codable {
    let index: ByteSlice
    let features: [FacetFeature]
}

struct ByteSlice: Codable {
    let byteStart: Int
    let byteEnd: Int
}

/// Facet の features は複数型があるため、型情報を持つラッパーで対応
struct FacetFeature: Codable {
    let type: String
    let did: String?      // mention
    let uri: String?      // link
    let tag: String?      // hashtag

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case did
        case uri
        case tag
    }
}

// MARK: - 埋め込みコンテンツ

/// AT Protocol の embed は $type により多様な形をとるため、既知の型を列挙
indirect enum PostEmbed: Codable {
    case images(EmbedImages)
    case external(EmbedExternal)
    case record(EmbedRecord)
    case recordWithMedia(EmbedRecordWithMedia)
    case video(EmbedVideo)
    case unknown

    enum CodingKeys: String, CodingKey {
        case type = "$type"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""

        switch type {
        case "app.bsky.embed.images#view":
            self = .images(try EmbedImages(from: decoder))
        case "app.bsky.embed.external#view":
            self = .external(try EmbedExternal(from: decoder))
        case "app.bsky.embed.record#view":
            self = .record(try EmbedRecord(from: decoder))
        case "app.bsky.embed.recordWithMedia#view":
            self = .recordWithMedia(try EmbedRecordWithMedia(from: decoder))
        case "app.bsky.embed.video#view":
            self = .video(try EmbedVideo(from: decoder))
        default:
            self = .unknown
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .images(let v): try v.encode(to: encoder)
        case .external(let v): try v.encode(to: encoder)
        case .record(let v): try v.encode(to: encoder)
        case .recordWithMedia(let v): try v.encode(to: encoder)
        case .video(let v): try v.encode(to: encoder)
        case .unknown: break
        }
    }
}

// MARK: - 画像埋め込み

struct EmbedImages: Codable {
    let images: [EmbedImageView]
}

struct EmbedImageView: Codable, Identifiable {
    let thumb: String
    let fullsize: String
    let alt: String
    let aspectRatio: AspectRatio?

    var id: String { thumb }
}

struct AspectRatio: Codable {
    let width: Int
    let height: Int
}

// MARK: - 外部リンク埋め込み（OGP）

struct EmbedExternal: Codable {
    let external: ExternalView
}

struct ExternalView: Codable {
    let uri: String
    let title: String
    let description: String?
    let thumb: String?
}

// MARK: - 引用リポスト埋め込み

struct EmbedRecord: Codable {
    let record: EmbedRecordView?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // record フィールドは削除済み・ブロック済みなど様々な $type で来るため、
        // app.bsky.embed.record#viewRecord 以外は nil として扱う
        self.record = try? container.decodeIfPresent(EmbedRecordView.self, forKey: .record)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(record, forKey: .record)
    }

    enum CodingKeys: String, CodingKey {
        case record
    }
}

struct EmbedRecordView: Codable {
    let type: String?
    let uri: String?
    let cid: String?
    let author: ProfileViewBasic?
    let value: PostRecordSimple?
    let indexedAt: String?

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case uri, cid, author, value, indexedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
        self.uri = try container.decodeIfPresent(String.self, forKey: .uri)
        self.cid = try container.decodeIfPresent(String.self, forKey: .cid)
        self.author = try container.decodeIfPresent(ProfileViewBasic.self, forKey: .author)
        // value は PostRecord 形式だが $type を持つため、decodeIfPresent で安全に
        self.value = try? container.decodeIfPresent(PostRecordSimple.self, forKey: .value)
        self.indexedAt = try container.decodeIfPresent(String.self, forKey: .indexedAt)
    }
}

/// 引用埋め込み内で使用するシンプルな投稿レコード（循環参照回避のため embed を持たない）
struct PostRecordSimple: Codable {
    let text: String
    let createdAt: String?
    let langs: [String]?
}

struct EmbedRecordWithMedia: Codable {
    let record: EmbedRecord
    let media: PostEmbed?
}

// MARK: - 動画埋め込み

struct EmbedVideo: Codable {
    let playlist: String?
    let thumbnail: String?
    let alt: String?
    let aspectRatio: AspectRatio?
}

// MARK: - 返信

struct ReplyRef: Codable {
    let root: PostViewRef?
    let parent: PostViewRef?
}

struct PostViewRef: Codable {
    let uri: String?
    let cid: String?
}

// MARK: - リポスト理由

struct FeedReason: Codable {
    let type: String
    let by: ProfileViewBasic?
    let indexedAt: String?

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case by
        case indexedAt
    }
}

// MARK: - ビューワー状態（自分との関係）

struct ViewerState: Codable {
    let repost: String?
    let like: String?
    let bookmarked: Bool?
    let threadMuted: Bool?
    let replyDisabled: Bool?
    let embeddingDisabled: Bool?
    let pinned: Bool?
}

// MARK: - ラベル（モデレーション）

struct ContentLabel: Codable {
    let src: String?
    let uri: String?
    let val: String
    let cts: String?
    let neg: Bool?
    let cid: String?
}

// MARK: - 投稿作成リクエスト

struct CreatePostRequest: Encodable {
    let repo: String
    let collection: String
    let record: PostRecordCreate

    init(repo: String, record: PostRecordCreate) {
        self.repo = repo
        self.collection = "app.bsky.feed.post"
        self.record = record
    }
}

struct PostRecordCreate: Encodable {
    let type: String
    let text: String
    let createdAt: String
    let langs: [String]?
    let facets: [Facet]?
    let reply: PostReplyRef?
    let embed: PostEmbedCreate?
    /// 投稿元クライアント名（設定でオンの場合のみセット）
    let via: String?
    /// BSAF タグ（BSAF 対応 Bot 投稿用）
    let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case text, createdAt, langs, facets, reply, embed, tags
        case via = "$via"
    }

    init(text: String, langs: [String]? = nil, facets: [Facet]? = nil, replyRef: PostReplyRef? = nil, embed: PostEmbedCreate? = nil, via: String? = nil, tags: [String]? = nil) {
        self.type = "app.bsky.feed.post"
        self.text = text
        self.createdAt = ISO8601DateFormatter().string(from: Date())
        // langs: 引数指定 → ユーザー設定 → Bluesky プリファレンス → 端末ロケールの優先順
        self.langs = langs ?? AppSettings.shared.resolvedPostLangs
        self.facets = facets
        self.reply = replyRef
        self.embed = embed
        self.via = via
        self.tags = tags
    }
}

/// 引用投稿用の embed レコード（app.bsky.embed.record 形式）
struct QuoteEmbedRecord: Codable {
    let type: String
    let record: StrongRef

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case record
    }

    init(uri: String, cid: String) {
        self.type = "app.bsky.embed.record"
        self.record = StrongRef(uri: uri, cid: cid)
    }
}

/// 外部リンク embed（app.bsky.embed.external）書き込み用
struct ExternalEmbedCreate: Encodable {
    let type: String = "app.bsky.embed.external"
    let external: ExternalCardCreate

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case external
    }
}

/// リンクカードのペイロード（投稿作成時）
struct ExternalCardCreate: Encodable {
    let uri: String
    let title: String
    let description: String
    let thumb: BlobRef?
}

/// 投稿作成時の embed（画像/動画/外部リンク/引用）を統一する enum（Encodable）
enum PostEmbedCreate: Encodable {
    case images(ImageEmbedCreate)
    case video(VideoEmbedCreate)
    case external(ExternalEmbedCreate)
    case record(QuoteEmbedRecord)
    case recordWithMedia(ImageEmbedCreate, QuoteEmbedRecord)

    func encode(to encoder: Encoder) throws {
        switch self {
        case .images(let v): try v.encode(to: encoder)
        case .video(let v): try v.encode(to: encoder)
        case .external(let v): try v.encode(to: encoder)
        case .record(let v): try v.encode(to: encoder)
        case .recordWithMedia(let media, let rec):
            var container = encoder.container(keyedBy: RecordWithMediaCodingKeys.self)
            try container.encode("app.bsky.embed.recordWithMedia", forKey: .type)
            try container.encode(media, forKey: .media)
            try container.encode(rec, forKey: .record)
        }
    }

    enum RecordWithMediaCodingKeys: String, CodingKey {
        case type = "$type"
        case media, record
    }
}

/// 動画 embed（app.bsky.embed.video）書き込み用
struct VideoEmbedCreate: Encodable {
    let type: String = "app.bsky.embed.video"
    let video: BlobRef
    let alt: String?
    let aspectRatio: AspectRatioCreate?

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case video, alt, aspectRatio
    }
}

/// 画像 embed（app.bsky.embed.images）書き込み用
struct ImageEmbedCreate: Encodable {
    let type: String = "app.bsky.embed.images"
    let images: [ImageEmbedItem]

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case images
    }
}

struct ImageEmbedItem: Encodable {
    let image: BlobRef
    let alt: String
    let aspectRatio: AspectRatioCreate?
}

struct AspectRatioCreate: Encodable {
    let width: Int
    let height: Int
}



// MARK: - uploadBlob レスポンス

struct UploadBlobResponse: Codable {
    let blob: BlobRef
}

struct BlobRef: Codable {
    let type: String
    let ref: BlobLink?
    let mimeType: String?
    let size: Int?

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case ref, mimeType, size
    }
}

struct BlobLink: Codable {
    let link: String
    enum CodingKeys: String, CodingKey {
        case link = "$link"
    }
}

// MARK: - 動画アップロードジョブステータス（app.bsky.video.uploadVideo レスポンス）

struct VideoUploadJobStatus: Codable {
    let jobId: String
    let did: String
    let state: String
    let blob: BlobRef?
    let error: String?
    let message: String?
}

/// getJobStatus / uploadVideo レスポンスが { jobStatus: {...} } でラップされている場合
struct VideoJobStatusWrapper: Codable {
    let jobStatus: VideoUploadJobStatus
}

// MARK: - getPosts レスポンス

struct GetPostsResponse: Codable {
    let posts: [PostView]
}

// MARK: - getRecord レスポンス（com.atproto.repo.getRecord）

struct GetRecordResponse: Codable {
    let uri: String
    let cid: String?
    let value: RepostRecordValue?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.uri = try container.decode(String.self, forKey: .uri)
        self.cid = try container.decodeIfPresent(String.self, forKey: .cid)
        // value は repost/like など複数の型が来るため、RepostRecordValue として安全にデコード
        self.value = try? container.decodeIfPresent(RepostRecordValue.self, forKey: .value)
    }

    enum CodingKeys: CodingKey {
        case uri, cid, value
    }
}

/// repost レコードの value（subject.uri を取得するために使用）
struct RepostRecordValue: Codable {
    let subject: RepostSubject?
}

struct RepostSubject: Codable {
    let uri: String?
    let cid: String?
}

// MARK: - スレッドゲート（app.bsky.feed.threadgate）

/// スレッドゲート作成リクエスト
struct ThreadgateCreate: Encodable {
    let post: String           // 対象投稿の AT-URI
    let allow: [ThreadgateRule]?   // nil = 制限なし, 空配列 = 全員禁止
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case post, allow, createdAt
        case type = "$type"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("app.bsky.feed.threadgate", forKey: .type)
        try container.encode(post, forKey: .post)
        try container.encodeIfPresent(allow, forKey: .allow)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

/// スレッドゲートのルール（多態性：$type で種類を判別）
enum ThreadgateRule: Encodable {
    case mention    // メンションされたユーザー
    case follower   // フォロワー
    case following  // フォロー中のユーザー

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .mention:   try container.encode("app.bsky.feed.threadgate#mentionRule",   forKey: .type)
        case .follower:  try container.encode("app.bsky.feed.threadgate#followerRule",  forKey: .type)
        case .following: try container.encode("app.bsky.feed.threadgate#followingRule", forKey: .type)
        }
    }

    enum CodingKeys: String, CodingKey {
        case type = "$type"
    }
}

/// スレッドゲートの UI 設定値
enum ThreadgateSetting: CaseIterable, Equatable {
    case everyone       // 制限なし（デフォルト）
    case noOne          // 全員禁止
    case mention        // メンションのみ
    case follower       // フォロワーのみ
    case following      // フォロー中のみ
    case mentionAndFollower   // メンション + フォロワー
    case mentionAndFollowing  // メンション + フォロー中

    /// nil = 制限なし（everyone）、空配列 = 全員禁止（noOne）
    var rules: [ThreadgateRule]? {
        switch self {
        case .everyone:             return nil
        case .noOne:                return []
        case .mention:              return [.mention]
        case .follower:             return [.follower]
        case .following:            return [.following]
        case .mentionAndFollower:   return [.mention, .follower]
        case .mentionAndFollowing:  return [.mention, .following]
        }
    }

    var displayName: String {
        switch self {
        case .everyone:             return String(localized: "compose.threadgate.everyone")
        case .noOne:                return String(localized: "compose.threadgate.noOne")
        case .mention:              return String(localized: "compose.threadgate.mention")
        case .follower:             return String(localized: "compose.threadgate.follower")
        case .following:            return String(localized: "compose.threadgate.following")
        case .mentionAndFollower:   return String(localized: "compose.threadgate.mentionAndFollower")
        case .mentionAndFollowing:  return String(localized: "compose.threadgate.mentionAndFollowing")
        }
    }

    var iconName: String {
        switch self {
        case .everyone:   return "bubble.left.and.bubble.right"
        case .noOne:      return "bubble.left.and.exclamationmark.bubble.right"
        default:          return "bubble.left.and.bubble.right.fill"
        }
    }
}

// MARK: - ポストゲート（app.bsky.feed.postgate）

/// ポストゲート作成リクエスト
struct PostgateCreate: Encodable {
    let post: String
    let embeddingRules: [PostgateEmbeddingRule]?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case post, embeddingRules, createdAt
        case type = "$type"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("app.bsky.feed.postgate", forKey: .type)
        try container.encode(post, forKey: .post)
        try container.encodeIfPresent(embeddingRules, forKey: .embeddingRules)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

/// 引用禁止ルール（app.bsky.feed.postgate#disableRule）
struct PostgateEmbeddingRule: Encodable {
    enum CodingKeys: String, CodingKey {
        case type = "$type"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("app.bsky.feed.postgate#disableRule", forKey: .type)
    }
}
