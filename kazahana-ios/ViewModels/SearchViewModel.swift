// SearchViewModel.swift
// kazahana-ios
// 検索画面の ViewModel

import Foundation
import Observation

enum SearchTab: String, CaseIterable, Identifiable {
    case people = "ユーザー"
    case posts = "投稿"

    var id: String { rawValue }
}

@Observable
final class SearchViewModel {
    var query = ""
    var selectedTab: SearchTab = .people

    // アクター検索結果
    var actors: [ProfileViewBasic] = []
    var isLoadingActors = false
    private var actorCursor: String?
    private var hasMoreActors = true

    // ポスト検索結果
    var posts: [PostView] = []
    var isLoadingPosts = false
    private var postCursor: String?
    private var hasMorePosts = true

    var errorMessage: String?

    private let searchService: SearchService
    private var searchTask: Task<Void, Never>?

    init(searchService: SearchService) {
        self.searchService = searchService
    }

    // MARK: - 検索実行

    @MainActor
    func search() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            actors = []
            posts = []
            return
        }

        // 既存のタスクをキャンセル
        searchTask?.cancel()
        searchTask = Task {
            switch selectedTab {
            case .people:
                await searchActors(reset: true)
            case .posts:
                await searchPosts(reset: true)
            }
        }
        await searchTask?.value
    }

    @MainActor
    func onQueryChange() {
        // デバウンスなしで即時検索（Xcode task キャンセルで対応）
        Task { await search() }
    }

    // MARK: - アクター検索

    @MainActor
    func searchActors(reset: Bool = false) async {
        guard !isLoadingActors else { return }
        if reset {
            actorCursor = nil
            hasMoreActors = true
        }
        guard hasMoreActors else { return }
        isLoadingActors = true
        errorMessage = nil

        do {
            let response = try await searchService.searchActors(
                query: query,
                cursor: actorCursor
            )
            if reset {
                actors = response.actors
            } else {
                actors.append(contentsOf: response.actors)
            }
            actorCursor = response.cursor
            hasMoreActors = response.cursor != nil
        } catch {
            if !(error is CancellationError) {
                errorMessage = error.localizedDescription
            }
        }
        isLoadingActors = false
    }

    @MainActor
    func loadMoreActors() async {
        await searchActors(reset: false)
    }

    // MARK: - ポスト検索

    @MainActor
    func searchPosts(reset: Bool = false) async {
        guard !isLoadingPosts else { return }
        if reset {
            postCursor = nil
            hasMorePosts = true
        }
        guard hasMorePosts else { return }
        isLoadingPosts = true
        errorMessage = nil

        do {
            let response = try await searchService.searchPosts(
                query: query,
                cursor: postCursor
            )
            if reset {
                posts = filterModeratedPosts(response.posts)
            } else {
                posts.append(contentsOf: filterModeratedPosts(response.posts))
            }
            postCursor = response.cursor
            hasMorePosts = response.cursor != nil
        } catch {
            if !(error is CancellationError) {
                errorMessage = error.localizedDescription
            }
        }
        isLoadingPosts = false
    }

    @MainActor
    func loadMorePosts() async {
        await searchPosts(reset: false)
    }

    // MARK: - Private

    private func filterModeratedPosts(_ posts: [PostView]) -> [PostView] {
        let service = ModerationService()
        return posts.filter { service.moderatePost($0).decision != .filter }
    }
}
