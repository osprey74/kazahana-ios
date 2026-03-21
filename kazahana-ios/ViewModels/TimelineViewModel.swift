// TimelineViewModel.swift
// kazahana-ios
// ホームタイムライン状態管理 ViewModel（カスタムフィード対応）

import SwiftUI
import Observation

@Observable
final class TimelineViewModel {

    // MARK: - State

    var posts: [FeedViewPost] = []
    var isLoading: Bool = false
    var isRefreshing: Bool = false
    var errorMessage: String? = nil

    // フィード
    var currentFeed: FeedSource = .following
    var savedFeeds: [GeneratorView] = []
    var savedLists: [GraphListView] = []
    var isLoadingFeeds: Bool = false

    // BSAF 重複検出
    /// primary 投稿 URI → 重複情報（PostCardView に渡す）
    var bsafDuplicateInfo: [String: BsafDuplicateInfo] = [:]
    private var bsafHiddenDuplicates: Set<String> = []

    // ページネーション
    private var cursor: String? = nil
    private var hasMore: Bool = true

    // ポーリング
    private var pollingTask: Task<Void, Never>? = nil

    // MARK: - Dependencies

    private let feedService: FeedService
    private let client: ATProtoClient

    // MARK: - Init

    init(client: ATProtoClient) {
        self.client = client
        self.feedService = FeedService(client: client)
    }

    // MARK: - フィードソース一覧（タブバー用）

    /// ホームタブバーに表示するフィードソース一覧（hiddenFeedURIs を除外し pinnedFeedURIs 順でソート）
    var visibleFeedSources: [FeedSource] {
        let settings = AppSettings.shared
        let allSources = buildAllFeedSources()
        let hiddenURIs = Set(settings.hiddenFeedURIs)
        let visible = allSources.filter { source in
            guard let uri = source.uri else { return true }
            return !hiddenURIs.contains(uri)
        }
        if settings.pinnedFeedURIs.isEmpty {
            return [.following] + visible
        }
        let ordered = visible.sorted { a, b in
            let ai = settings.pinnedFeedURIs.firstIndex(of: a.uri ?? "") ?? Int.max
            let bi = settings.pinnedFeedURIs.firstIndex(of: b.uri ?? "") ?? Int.max
            return ai < bi
        }
        return [.following] + ordered
    }

    /// 全フィードソース（設定画面用: hidden も含む）
    var allFeedSources: [FeedSource] {
        buildAllFeedSources()
    }

    private func buildAllFeedSources() -> [FeedSource] {
        savedFeeds.map { .custom($0) } + savedLists.map { .list($0) }
    }

    // MARK: - フィード選択

    @MainActor
    func selectFeed(_ feed: FeedSource) async {
        guard feed != currentFeed else { return }
        currentFeed = feed
        posts = []
        cursor = nil
        hasMore = true
        await loadInitial()
    }

    @MainActor
    func loadSavedFeeds() async {
        guard !isLoadingFeeds else { return }
        isLoadingFeeds = true
        guard let actor = client.currentSession?.did else {
            isLoadingFeeds = false
            return
        }
        do {
            let result = try await feedService.getAllSavedFeedItems(actor: actor)
            savedFeeds = result.feeds
            savedLists = result.lists
        } catch {
            // フィード取得失敗はサイレント（フォロー中フィードのみ表示）
            print("[FeedSelector] getAllSavedFeedItems error: \(error)")
        }
        isLoadingFeeds = false
    }

    // MARK: - Actions

    /// 初回読み込み
    @MainActor
    func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        cursor = nil
        hasMore = true

        do {
            let response = try await fetchFeed(cursor: nil)
            posts = filterAndProcessPosts(response.feed)
            cursor = response.cursor
            hasMore = response.cursor != nil
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Pull-to-Refresh
    @MainActor
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        cursor = nil
        hasMore = true

        do {
            let response = try await fetchFeed(cursor: nil)
            posts = filterAndProcessPosts(response.feed)
            cursor = response.cursor
            hasMore = response.cursor != nil
        } catch {
            errorMessage = error.localizedDescription
        }

        isRefreshing = false
    }

    /// 無限スクロール（次ページ読み込み）
    @MainActor
    func loadMore() async {
        guard !isLoading, hasMore, let cursor else { return }
        isLoading = true

        do {
            let response = try await fetchFeed(cursor: cursor)
            // 新規投稿をモデレーションフィルタのみ適用して追加
            let newFiltered = response.feed.filter {
                ModerationService().moderatePost($0.post).decision != .filter
            }
            posts.append(contentsOf: newFiltered)
            // 全投稿でBSAF重複を再計算してフィルタ適用
            let allPosts = posts
            computeBsafDuplicates(allPosts)
            posts = applyBsafFilters(allPosts)
            self.cursor = response.cursor
            hasMore = response.cursor != nil
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// 投稿削除後にローカルリストから除去
    @MainActor
    func removePost(uri: String) {
        posts.removeAll { $0.post.uri == uri }
    }

    // MARK: - ポーリング

    /// 自動更新ポーリングを開始する（指定間隔で refresh を繰り返す）
    @MainActor
    func startPolling(intervalSeconds: Int) {
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(intervalSeconds))
                guard !Task.isCancelled, let self else { break }
                await self.refresh()
            }
        }
    }

    /// ポーリングを停止する
    @MainActor
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Private

    /// モデレーション + BSAF フィルタ + BSAF 重複非表示を適用する
    private func filterAndProcessPosts(_ posts: [FeedViewPost]) -> [FeedViewPost] {
        let moderationFiltered = posts.filter {
            ModerationService().moderatePost($0.post).decision != .filter
        }
        computeBsafDuplicates(moderationFiltered)
        return applyBsafFilters(moderationFiltered)
    }

    /// BSAF 重複グループを計算し bsafDuplicateInfo / bsafHiddenDuplicates を更新する
    private func computeBsafDuplicates(_ posts: [FeedViewPost]) {
        let settings = AppSettings.shared
        var newDuplicateInfo: [String: BsafDuplicateInfo] = [:]
        var newHiddenDuplicates: Set<String> = []

        guard settings.bsafEnabled else {
            bsafDuplicateInfo = [:]
            bsafHiddenDuplicates = []
            return
        }

        // type|value|time|target でグループ化
        var groups: [String: [(uri: String, handle: String)]] = [:]
        for feedPost in posts {
            guard let tags = feedPost.post.record.tags,
                  let parsed = BsafService.parseBsafTags(tags) else { continue }
            let key = BsafService.duplicateKey(parsed)
            let entry = (uri: feedPost.post.uri, handle: feedPost.post.author.handle)
            groups[key, default: []].append(entry)
        }

        // 先頭が primary、残りは非表示
        for group in groups.values where group.count > 1 {
            let primary = group[0]
            let rest = Array(group.dropFirst())
            newDuplicateInfo[primary.uri] = BsafDuplicateInfo(
                duplicateUris: rest.map { $0.uri },
                duplicateHandles: rest.map { $0.handle }
            )
            for dup in rest { newHiddenDuplicates.insert(dup.uri) }
        }

        bsafDuplicateInfo = newDuplicateInfo
        bsafHiddenDuplicates = newHiddenDuplicates
    }

    /// BSAF フィルタと重複非表示を適用する（モデレーション済みリストに対して）
    private func applyBsafFilters(_ posts: [FeedViewPost]) -> [FeedViewPost] {
        let settings = AppSettings.shared
        return posts.filter { feedPost in
            // BSAF 重複非表示
            if bsafHiddenDuplicates.contains(feedPost.post.uri) { return false }
            // BSAF フィルタ（有効時のみ）
            if settings.bsafEnabled,
               let tags = feedPost.post.record.tags,
               let parsed = BsafService.parseBsafTags(tags),
               let bot = settings.findRegisteredBot(did: feedPost.post.author.did) {
                return BsafService.shouldShowBsafPost(parsed, bot: bot)
            }
            return true
        }
    }

    private func fetchFeed(cursor: String?) async throws -> TimelineResponse {
        switch currentFeed {
        case .following:
            return try await feedService.getTimeline(limit: 50, cursor: cursor)
        case .custom(let generator):
            return try await feedService.getFeed(feedURI: generator.uri, limit: 50, cursor: cursor)
        case .list(let listView):
            return try await feedService.getListFeed(listURI: listView.uri, limit: 50, cursor: cursor)
        }
    }
}
