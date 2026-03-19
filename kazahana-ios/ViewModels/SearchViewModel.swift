// SearchViewModel.swift
// kazahana-ios
// 検索画面の ViewModel

import Foundation
import Observation
import SwiftUI

enum SearchTab: String, CaseIterable, Identifiable {
    case people = "people"
    case posts  = "posts"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .people: return String(localized: "search.people")
        case .posts:  return String(localized: "search.posts")
        }
    }
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

    // 検索履歴（最新が先頭、最大20件）
    var searchHistory: [String] = []

    private static let historyKey = "searchHistory"
    private static let historyLimit = 20

    private let searchService: SearchService
    private var searchTask: Task<Void, Never>?

    init(searchService: SearchService) {
        self.searchService = searchService
        loadHistory()
    }

    // MARK: - 検索履歴

    private func loadHistory() {
        searchHistory = UserDefaults.standard.stringArray(forKey: Self.historyKey) ?? []
    }

    private func saveHistory() {
        UserDefaults.standard.set(searchHistory, forKey: Self.historyKey)
    }

    private func addToHistory(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        searchHistory.removeAll { $0 == trimmed }
        searchHistory.insert(trimmed, at: 0)
        if searchHistory.count > Self.historyLimit {
            searchHistory = Array(searchHistory.prefix(Self.historyLimit))
        }
        saveHistory()
    }

    func deleteHistory(at offsets: IndexSet) {
        searchHistory.remove(atOffsets: offsets)
        saveHistory()
    }

    func clearAllHistory() {
        searchHistory.removeAll()
        saveHistory()
    }

    // MARK: - 検索実行

    @MainActor
    func search() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            actors = []
            posts = []
            return
        }

        addToHistory(query)

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
