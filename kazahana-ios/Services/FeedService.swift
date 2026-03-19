// FeedService.swift
// kazahana-ios
// カスタムフィード・フォローフィード等の取得サービス

import Foundation

// MARK: - getPreferences レスポンス

struct PreferencesResponse: Codable {
    let preferences: [PreferenceItem]
}

/// preferences 配列の各要素（$type でどの preference か判別）
/// 未知のフィールドを含む多様な preference に対応するため手動デコード
struct PreferenceItem: Codable {
    let type: String

    // savedFeedsPrefV2 の items
    let items: [SavedFeedPrefV2]?

    // savedFeedsPref (v1) の pinned/saved
    let pinned: [String]?
    let saved: [String]?

    // languagesPref の postLanguages
    let postLanguages: [String]?

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case items, pinned, saved, postLanguages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type          = (try? container.decode(String.self, forKey: .type)) ?? ""
        self.items         = try? container.decodeIfPresent([SavedFeedPrefV2].self, forKey: .items)
        self.pinned        = try? container.decodeIfPresent([String].self, forKey: .pinned)
        self.saved         = try? container.decodeIfPresent([String].self, forKey: .saved)
        self.postLanguages = try? container.decodeIfPresent([String].self, forKey: .postLanguages)
    }
}

struct SavedFeedPrefV2: Codable {
    let id: String?
    let type: String
    let value: String
    let pinned: Bool?   // optional に変更（一部環境では来ない場合がある）

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id     = try? container.decodeIfPresent(String.self, forKey: .id)
        self.type   = (try? container.decode(String.self, forKey: .type)) ?? ""
        self.value  = (try? container.decode(String.self, forKey: .value)) ?? ""
        self.pinned = try? container.decodeIfPresent(Bool.self, forKey: .pinned)
    }

    enum CodingKeys: CodingKey {
        case id, type, value, pinned
    }
}

// MARK: - getFeedGenerators レスポンス

struct FeedGeneratorsResponse: Codable {
    let feeds: [GeneratorView]
}

struct GeneratorView: Codable, Identifiable, Hashable {
    let uri: String
    let cid: String
    let did: String?
    let creator: ProfileViewBasic
    let displayName: String
    let description: String?
    let avatar: String?
    let likeCount: Int?
    let indexedAt: String

    var id: String { uri }

    static func == (lhs: GeneratorView, rhs: GeneratorView) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct FeedService {
    private let client: ATProtoClient

    init(client: ATProtoClient) {
        self.client = client
    }

    /// 保存済みフィードを getPreferences 経由で取得する
    /// v2 (savedFeedsPrefV2) と v1 (savedFeedsPref) の両方に対応
    func getSavedFeeds() async throws -> [GeneratorView] {
        // Step 1: actor preferences を取得
        let prefResponse: PreferencesResponse = try await client.get(
            nsid: "app.bsky.actor.getPreferences",
            params: [:]
        )
        print("[FeedService] preferences count: \(prefResponse.preferences.count)")
        for pref in prefResponse.preferences {
            print("[FeedService] pref type: \(pref.type)")
        }

        // savedFeedsPrefV2 から feed URI を収集
        var feedURIs: [String] = []

        for pref in prefResponse.preferences {
            if pref.type == "app.bsky.actor.defs#savedFeedsPrefV2",
               let items = pref.items {
                let uris = items.filter { $0.type == "feed" }.map { $0.value }
                feedURIs.append(contentsOf: uris)
                print("[FeedService] v2 feed URIs: \(uris)")
            } else if pref.type == "app.bsky.actor.defs#savedFeedsPref",
                      let pinned = pref.pinned {
                // v1 の pinned にフィード URI が含まれる（"following" 等の特殊値を除外）
                let feedOnlyPinned = pinned.filter { $0.hasPrefix("at://") && $0.contains("/app.bsky.feed.generator/") }
                feedURIs.append(contentsOf: feedOnlyPinned)
                print("[FeedService] v1 pinned URIs: \(pinned) → filtered: \(feedOnlyPinned)")
            }
        }

        // 重複除去
        feedURIs = Array(Set(feedURIs))
        guard !feedURIs.isEmpty else {
            print("[FeedService] no feed URIs found")
            return []
        }

        // Step 2: GeneratorView を一括取得
        let queryItems = feedURIs.map { URLQueryItem(name: "feeds", value: $0) }
        let generators: FeedGeneratorsResponse = try await client.getWithArrayParams(
            nsid: "app.bsky.feed.getFeedGenerators",
            queryItems: queryItems
        )
        print("[FeedService] generators: \(generators.feeds.map { $0.displayName })")
        return generators.feeds
    }

    /// カスタムフィードのタイムラインを取得する
    func getFeed(feedURI: String, limit: Int = 50, cursor: String? = nil) async throws -> TimelineResponse {
        var params: [String: String] = ["feed": feedURI, "limit": "\(limit)"]
        if let cursor = cursor { params["cursor"] = cursor }
        return try await client.get(nsid: "app.bsky.feed.getFeed", params: params)
    }

    /// フォローしているユーザーのタイムラインを取得する
    func getTimeline(limit: Int = 50, cursor: String? = nil) async throws -> TimelineResponse {
        var params: [String: String] = ["limit": "\(limit)"]
        if let cursor = cursor { params["cursor"] = cursor }
        return try await client.get(nsid: "app.bsky.feed.getTimeline", params: params)
    }
}

// MARK: - フィード識別子

enum FeedSource: Equatable, Hashable {
    case following                  // フォロー中タイムライン
    case custom(GeneratorView)      // カスタムフィード

    var displayName: String {
        switch self {
        case .following:         return "フォロー中"
        case .custom(let gen):   return gen.displayName
        }
    }

    var icon: String {
        switch self {
        case .following:       return "person.2.fill"
        case .custom:          return "list.star"
        }
    }
}
