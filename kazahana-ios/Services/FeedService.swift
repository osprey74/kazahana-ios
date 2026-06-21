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

// MARK: - グラフリスト モデル

/// app.bsky.graph.defs#listViewBasic（creator フィールドなし）
struct GraphListViewBasic: Codable, Identifiable, Hashable {
    let uri: String
    let cid: String
    let name: String
    let purpose: String
    let avatar: String?
    let listItemCount: Int?
    let indexedAt: String?

    var id: String { uri }

    static func == (lhs: GraphListViewBasic, rhs: GraphListViewBasic) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// app.bsky.graph.defs#listView（creator フィールドあり）
struct GraphListView: Codable, Identifiable, Hashable {
    let uri: String
    let cid: String
    let name: String
    let purpose: String
    let avatar: String?
    let listItemCount: Int?
    let description: String?
    let creator: ProfileViewBasic
    let indexedAt: String?

    var id: String { uri }

    static func == (lhs: GraphListView, rhs: GraphListView) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct GetListsResponse: Codable {
    let lists: [GraphListView]
    let cursor: String?
}

struct GetActorFeedsResponse: Codable {
    let feeds: [GeneratorView]
    let cursor: String?
}

struct GetListResponse: Codable {
    let list: GraphListView
    let cursor: String?
}

struct ListItemView: Codable {
    let uri: String
    let subject: ProfileViewBasic
}

// MARK: - スターターパック モデル

struct StarterPackView: Codable, Identifiable {
    let uri: String
    let cid: String
    let record: StarterPackRecord
    let creator: ProfileViewBasic
    let list: GraphListViewBasic?
    let listItemCount: Int?
    let joinedWeekCount: Int?
    let joinedAllTimeCount: Int?
    let indexedAt: String

    var id: String { uri }
}

struct StarterPackRecord: Codable {
    let name: String
    let description: String?
}

struct StarterPackViewBasic: Codable, Identifiable, Hashable {
    let uri: String
    let cid: String
    let record: StarterPackRecord
    let creator: ProfileViewBasic
    let listItemCount: Int?
    let joinedWeekCount: Int?
    let joinedAllTimeCount: Int?
    let indexedAt: String

    var id: String { uri }

    static func == (lhs: StarterPackViewBasic, rhs: StarterPackViewBasic) -> Bool { lhs.uri == rhs.uri }
    func hash(into hasher: inout Hasher) { hasher.combine(uri) }
}

struct GetActorStarterPacksResponse: Codable {
    let starterPacks: [StarterPackViewBasic]
    let cursor: String?
}

struct GetStarterPackResponse: Codable {
    let starterPack: StarterPackView
}

struct GetListMembersResponse: Codable {
    let list: GraphListView
    let items: [ListItemView]
    let cursor: String?
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
                // pinned == true のフィードのみ表示（ピンを外したフィードは除外）
                let uris = items.filter { $0.type == "feed" && $0.pinned != false }.map { $0.value }
                feedURIs.append(contentsOf: uris)
                print("[FeedService] v2 feed URIs (pinned): \(uris)")
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

    /// リストフィードのタイムラインを取得する
    func getListFeed(listURI: String, limit: Int = 50, cursor: String? = nil) async throws -> TimelineResponse {
        var params: [String: String] = ["list": listURI, "limit": "\(limit)"]
        if let cursor = cursor { params["cursor"] = cursor }
        return try await client.get(nsid: "app.bsky.feed.getListFeed", params: params)
    }

    /// 自分のキュレーションリストを取得する
    func getMyLists(actor: String, limit: Int = 100) async throws -> [GraphListView] {
        let response: GetListsResponse = try await client.get(
            nsid: "app.bsky.graph.getLists",
            params: ["actor": actor, "limit": "\(limit)"]
        )
        return response.lists.filter { $0.purpose == "app.bsky.graph.defs#curatelist" }
    }

    /// 指定アクターが作成したカスタムフィード一覧を取得する
    func getActorFeeds(actor: String, limit: Int = 100, cursor: String? = nil) async throws -> GetActorFeedsResponse {
        var params: [String: String] = ["actor": actor, "limit": "\(limit)"]
        if let cursor = cursor { params["cursor"] = cursor }
        return try await client.get(nsid: "app.bsky.feed.getActorFeeds", params: params)
    }

    /// 指定アクターのリスト一覧を取得する
    func getLists(actor: String, limit: Int = 100, cursor: String? = nil) async throws -> GetListsResponse {
        var params: [String: String] = ["actor": actor, "limit": "\(limit)"]
        if let cursor = cursor { params["cursor"] = cursor }
        return try await client.get(nsid: "app.bsky.graph.getLists", params: params)
    }

    /// 指定アクターが作成したスターターパック一覧を取得する
    func getActorStarterPacks(actor: String, limit: Int = 50, cursor: String? = nil) async throws -> GetActorStarterPacksResponse {
        var params: [String: String] = ["actor": actor, "limit": "\(limit)"]
        if let cursor = cursor { params["cursor"] = cursor }
        return try await client.get(nsid: "app.bsky.graph.getActorStarterPacks", params: params)
    }

    /// スターターパックを取得する
    func getStarterPack(uri: String) async throws -> GetStarterPackResponse {
        return try await client.get(nsid: "app.bsky.graph.getStarterPack", params: ["starterPack": uri])
    }

    /// リストのメンバー一覧を取得する
    func getListMembers(listURI: String, limit: Int = 50, cursor: String? = nil) async throws -> GetListMembersResponse {
        var params: [String: String] = ["list": listURI, "limit": "\(limit)"]
        if let cursor = cursor { params["cursor"] = cursor }
        return try await client.get(nsid: "app.bsky.graph.getList", params: params)
    }

    /// 保存済みフィードとリスト両方を返す（横スクロールタブバー用）
    func getAllSavedFeedItems(actor: String) async throws -> (feeds: [GeneratorView], lists: [GraphListView]) {
        // Step 1: preferences を取得
        let prefResponse: PreferencesResponse = try await client.get(
            nsid: "app.bsky.actor.getPreferences",
            params: [:]
        )

        var feedURIs: [String] = []
        var listURIs: [String] = []

        for pref in prefResponse.preferences {
            if pref.type == "app.bsky.actor.defs#savedFeedsPrefV2",
               let items = pref.items {
                // pinned == true のフィード/リストのみ表示（ピンを外したフィードは除外）
                feedURIs.append(contentsOf: items.filter { $0.type == "feed" && $0.pinned != false }.map { $0.value })
                listURIs.append(contentsOf: items.filter { $0.type == "list" && $0.pinned != false }.map { $0.value })
            } else if pref.type == "app.bsky.actor.defs#savedFeedsPref",
                      let pinned = pref.pinned {
                let feedOnly = pinned.filter { $0.hasPrefix("at://") && $0.contains("/app.bsky.feed.generator/") }
                feedURIs.append(contentsOf: feedOnly)
            }
        }

        // Step 2: フィード GeneratorView を一括取得
        feedURIs = Array(Set(feedURIs))
        var feeds: [GeneratorView] = []
        if !feedURIs.isEmpty {
            let queryItems = feedURIs.map { URLQueryItem(name: "feeds", value: $0) }
            let generators: FeedGeneratorsResponse = try await client.getWithArrayParams(
                nsid: "app.bsky.feed.getFeedGenerators",
                queryItems: queryItems
            )
            feeds = generators.feeds
        }

        // Step 3: 保存されたリストを個別取得
        listURIs = Array(Set(listURIs))
        var savedLists: [GraphListView] = []
        for listURI in listURIs {
            do {
                let response: GetListResponse = try await client.get(
                    nsid: "app.bsky.graph.getList",
                    params: ["list": listURI, "limit": "1"]
                )
                if response.list.purpose == "app.bsky.graph.defs#curatelist" {
                    savedLists.append(response.list)
                }
            } catch {
                print("[FeedService] getList failed for \(listURI): \(error)")
            }
        }

        // Step 4: 自分のキュレーションリストをマージ（重複除去）
        let myLists = (try? await getMyLists(actor: actor)) ?? []
        var seen = Set<String>(savedLists.map { $0.uri })
        for list in myLists where !seen.contains(list.uri) {
            seen.insert(list.uri)
            savedLists.append(list)
        }

        return (feeds: feeds, lists: savedLists)
    }
}

// MARK: - フィード識別子

enum FeedSource: Equatable, Hashable {
    case following                  // フォロー中タイムライン
    case custom(GeneratorView)      // カスタムフィード
    case list(GraphListView)        // キュレーションリスト

    var displayName: String {
        switch self {
        case .following:           return String(localized: "feed.following")
        case .custom(let gen):     return gen.displayName
        case .list(let listView):  return listView.name
        }
    }

    var icon: String {
        switch self {
        case .following:  return "person.2.fill"
        case .custom:     return "list.star"
        case .list:       return "list.bullet.rectangle"
        }
    }

    /// フィード/リストを識別するURI（following は nil）
    var uri: String? {
        switch self {
        case .following:           return nil
        case .custom(let gen):     return gen.uri
        case .list(let listView):  return listView.uri
        }
    }
}
