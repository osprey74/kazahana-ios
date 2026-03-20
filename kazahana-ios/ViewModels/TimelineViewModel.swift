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
            posts = filterModeratedPosts(response.feed)
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
            posts = filterModeratedPosts(response.feed)
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
            posts.append(contentsOf: filterModeratedPosts(response.feed))
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

    /// filter 判定の投稿をタイムラインから除外する
    private func filterModeratedPosts(_ posts: [FeedViewPost]) -> [FeedViewPost] {
        let service = ModerationService()
        return posts.filter { service.moderatePost($0.post).decision != .filter }
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
