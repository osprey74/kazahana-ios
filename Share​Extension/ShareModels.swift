// ShareModels.swift
// Share​Extension
// Share Extension が必要とする型の定義（メインアプリとの共通型）

import Foundation
import Security

// MARK: - Session

struct Session: Codable, Equatable {
    let did: String
    let handle: String
    let accessJwt: String
    let refreshJwt: String
    let pdsHost: String

    init(did: String, handle: String, accessJwt: String, refreshJwt: String, pdsHost: String = "https://bsky.social") {
        self.did = did
        self.handle = handle
        self.accessJwt = accessJwt
        self.refreshJwt = refreshJwt
        self.pdsHost = pdsHost
    }
}

// MARK: - SessionStore（Share Extension 用・読み取りのみ）

final class SessionStore {

    private enum Keys {
        static let service     = "com.osprey74.kazahana"
        static let accessGroup = "9L6A9KDH5P.com.osprey74.kazahana"
        static let suiteName   = "group.com.osprey74.kazahana"
        static let activeDIDKey = "activeAccountDID"
        static func sessionCacheKey(for did: String) -> String { "sessionCache:\(did)" }
    }

    /// Keychain アクセシビリティを ThisDeviceOnly → 通常に移行する（削除→再追加）
    /// Share Extension からも呼び出せるよう、メインアプリと同じ処理を実施する
    private func migrateKeychainAccessibilityIfNeeded() {
        let migratedKey = "keychainAccessMigrated_v2"
        let sharedDefaults = UserDefaults(suiteName: Keys.suiteName) ?? .standard
        guard !sharedDefaults.bool(forKey: migratedKey) else { return }

        let searchQuery: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      Keys.service,
            kSecAttrAccessGroup as String:  Keys.accessGroup,
            kSecReturnData as String:       true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String:       kSecMatchLimitAll
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(searchQuery as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else {
            sharedDefaults.set(true, forKey: migratedKey)
            return
        }
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  let data = item[kSecValueData as String] as? Data else { continue }
            let deleteQuery: [String: Any] = [
                kSecClass as String:           kSecClassGenericPassword,
                kSecAttrService as String:     Keys.service,
                kSecAttrAccount as String:     account,
                kSecAttrAccessGroup as String: Keys.accessGroup
            ]
            SecItemDelete(deleteQuery as CFDictionary)
            let addQuery: [String: Any] = [
                kSecClass as String:           kSecClassGenericPassword,
                kSecAttrService as String:     Keys.service,
                kSecAttrAccount as String:     account,
                kSecAttrAccessGroup as String: Keys.accessGroup,
                kSecValueData as String:       data,
                kSecAttrAccessible as String:  kSecAttrAccessibleAfterFirstUnlock
            ]
            SecItemAdd(addQuery as CFDictionary, nil)
        }
        sharedDefaults.set(true, forKey: migratedKey)
    }

    /// アクティブアカウントのセッションを返す
    /// App Group UserDefaults キャッシュ → Keychain の順で検索する
    func load() -> Session? {
        migrateKeychainAccessibilityIfNeeded()
        let sharedDefaults = UserDefaults(suiteName: Keys.suiteName) ?? .standard

        if let did = sharedDefaults.string(forKey: Keys.activeDIDKey) {
            // 最優先: App Group UserDefaults キャッシュ（Keychain 共有の信頼性に依存しない）
            if let data = sharedDefaults.data(forKey: Keys.sessionCacheKey(for: did)),
               let session = try? JSONDecoder().decode(Session.self, from: data) {
                return session
            }
            // Keychain フォールバック
            if let session = keychainLoad(account: "session:\(did)") {
                return session
            }
        }

        // 旧形式フォールバック（マイグレーション前の互換性）
        if let session = keychainLoad(account: "session") {
            return session
        }

        // 全 session:* アイテムを検索（最終フォールバック）
        return searchAnySession()
    }

    private func keychainLoad(account: String) -> Session? {
        let query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     Keys.service,
            kSecAttrAccount as String:     account,
            kSecAttrAccessGroup as String: Keys.accessGroup,
            kSecReturnData as String:      true,
            kSecMatchLimit as String:      kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    private func searchAnySession() -> Session? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      Keys.service,
            kSecAttrAccessGroup as String:  Keys.accessGroup,
            kSecReturnData as String:       true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String:       kSecMatchLimitAll
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return nil }
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  account.hasPrefix("session:"),
                  let data = item[kSecValueData as String] as? Data,
                  let session = try? JSONDecoder().decode(Session.self, from: data) else { continue }
            return session
        }
        return nil
    }
}

// MARK: - ShareSettings（UserDefaults から via / langs を読み取る）

struct ShareSettings {
    /// showVia が true の場合に付与するクライアント名
    static let viaName = "kazahana for iOS"

    /// メインアプリと共有する App Group UserDefaults
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.osprey74.kazahana") ?? .standard
    }

    static var via: String? {
        let showVia = defaults.object(forKey: "showVia") as? Bool ?? false
        return showVia ? viaName : nil
    }

    /// 投稿レコードに渡す langs 配列（ユーザー設定 > 端末ロケール）
    static var langs: [String] {
        let langRaw = defaults.string(forKey: "postLanguageSetting") ?? "system"
        if langRaw != "system" {
            return [langRaw]
        }
        let locale = Locale.current.language.languageCode?.identifier ?? "ja"
        return [locale]
    }
}

// MARK: - BlobRef（画像アップロードレスポンス）

struct BlobRef: Codable {
    let type: String
    let ref: BlobLink?
    let mimeType: String?
    let size: Int?

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case ref = "ref"
        case mimeType
        case size
    }
}

struct BlobLink: Codable {
    let link: String
    enum CodingKeys: String, CodingKey {
        case link = "$link"
    }
}

// MARK: - Facet（RichText）

struct Facet: Codable {
    let index: FacetIndex
    let features: [FacetFeature]
}

struct FacetIndex: Codable {
    let byteStart: Int
    let byteEnd: Int
}

struct FacetFeature: Codable {
    let type: String
    let uri: String?
    let did: String?
    let tag: String?

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case uri
        case did
        case tag
    }
}

// MARK: - Post Embed

struct PostRefStrong: Codable {
    let uri: String
    let cid: String
}

struct PostReplyRef: Codable {
    let root: PostRefStrong
    let parent: PostRefStrong
}

struct ImageEmbedItem: Codable {
    let image: BlobRef
    let alt: String
    let aspectRatio: AspectRatioCreate?
}

struct ImageEmbedCreate: Codable {
    let type = "app.bsky.embed.images"
    let images: [ImageEmbedItem]
    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case images
    }
}

struct AspectRatioCreate: Codable {
    let width: Int
    let height: Int
}

/// app.bsky.embed.external（リンクカード）
struct ExternalEmbedCreate: Encodable {
    let type = "app.bsky.embed.external"
    let external: ExternalCard
    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case external
    }
}

struct ExternalCard: Encodable {
    let uri: String
    let title: String
    let description: String
    let thumb: BlobRef?
}

enum PostEmbedCreate: Encodable {
    case images(ImageEmbedCreate)
    case external(ExternalEmbedCreate)

    func encode(to encoder: Encoder) throws {
        switch self {
        case .images(let e):    try e.encode(to: encoder)
        case .external(let e):  try e.encode(to: encoder)
        }
    }
}

// MARK: - PostRecord

struct PostRecordCreate: Encodable {
    let type = "app.bsky.feed.post"
    let text: String
    let facets: [Facet]?
    let replyRef: PostReplyRef?
    let embed: PostEmbedCreate?
    let langs: [String]?
    let createdAt: String = ISO8601DateFormatter().string(from: Date())
    let via: String?

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case text, facets
        case replyRef = "reply"
        case embed, langs, createdAt, via
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(facets, forKey: .facets)
        try container.encodeIfPresent(replyRef, forKey: .replyRef)
        try container.encodeIfPresent(embed, forKey: .embed)
        try container.encodeIfPresent(langs, forKey: .langs)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(via, forKey: .via)
    }
}

struct CreateRecordRequest: Encodable {
    let repo: String
    let collection: String
    let record: PostRecordCreate
}

struct CreateRecordResponse: Decodable {
    let uri: String
    let cid: String
}

struct UploadBlobResponse: Decodable {
    let blob: BlobRef
}

// MARK: - ATProto エラー

enum ATProtoError: Error {
    case unauthorized
    case httpError(Int, String?)
    case decodingError(Error)
    case unknown(Error)
}
