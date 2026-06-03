// ProfileViewModel.swift
// kazahana-ios
// プロフィール画面の ViewModel

import Foundation
import Observation
import SwiftUI

enum ProfileTab: String, CaseIterable {
    case posts        = "posts"
    case replies      = "replies"
    case media        = "media"
    case likes        = "likes"
    case bookmarks    = "bookmarks"
    case starterPacks = "starterPacks"

    var displayName: String {
        switch self {
        case .posts:        return String(localized: "profile.posts")
        case .replies:      return String(localized: "profile.replies")
        case .media:        return String(localized: "profile.media")
        case .likes:        return String(localized: "profile.likes")
        case .bookmarks:    return String(localized: "profile.bookmarks")
        case .starterPacks: return String(localized: "profile.starterPacks")
        }
    }
}

@Observable
final class ProfileViewModel {
    var profile: ProfileView?
    var posts: [FeedViewPost] = []
    var isLoadingProfile = false
    var isLoadingPosts = false
    var isRefreshing = false
    var isFollowLoading = false
    var isMuteLoading = false
    var isBlockLoading = false
    var errorMessage: String?

    // タブ管理
    var selectedTab: ProfileTab = .posts
    // タブ別フィードキャッシュ
    var tabFeeds: [ProfileTab: [FeedViewPost]] = [:]
    var tabCursors: [ProfileTab: String?] = [:]
    var tabHasMore: [ProfileTab: Bool] = [:]
    var tabIsLoading: [ProfileTab: Bool] = [:]

    // ピン留め投稿
    var pinnedPost: PostView? = nil
    var isLoadingPinnedPost = false

    // プロフィール内検索
    var profileSearchQuery: String = ""
    var profileSearchResults: [PostView] = []
    var isSearchingInProfile = false
    var profileSearchCursor: String? = nil
    var profileSearchHasMore = false
    private var profileSearchTask: Task<Void, Never>?

    private var cursor: String?
    private var hasMore = true
    let actor: String

    private let graphService: GraphService
    private var searchService: SearchService?
    private var feedService: FeedService?
    private var postService: PostService?

    init(actor: String, graphService: GraphService, searchService: SearchService? = nil, feedService: FeedService? = nil, postService: PostService? = nil) {
        self.actor = actor
        self.graphService = graphService
        self.searchService = searchService
        self.feedService = feedService
        self.postService = postService
        // feeds/lists/bookmarks タブはフィードポストを持たないので tabFeeds から除外
        let postTabs: [ProfileTab] = [.posts, .replies, .media, .likes]
        for tab in postTabs {
            tabFeeds[tab] = []
            tabCursors[tab] = nil
            tabHasMore[tab] = true
            tabIsLoading[tab] = false
        }
    }

    var currentFeed: [FeedViewPost] { tabFeeds[selectedTab] ?? [] }
    var isCurrentTabLoading: Bool { tabIsLoading[selectedTab] ?? false }

    // MARK: - プロフィール読み込み

    @MainActor
    func loadProfile() async {
        guard !isLoadingProfile else { return }
        isLoadingProfile = true
        errorMessage = nil

        do {
            profile = try await graphService.getProfile(actor: actor)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingProfile = false
    }

    // MARK: - 投稿一覧読み込み（後方互換）

    @MainActor
    func loadPosts() async {
        await loadTab(.posts)
    }

    @MainActor
    func loadMorePosts() async {
        await loadMoreTab(.posts)
    }

    // MARK: - タブ別フィード読み込み

    @MainActor
    func loadTab(_ tab: ProfileTab) async {
        // starterPacks / bookmarks タブは専用メソッドで処理
        if tab == .starterPacks {
            // StarterPackListTabView が自前でロードするため何もしない
            return
        }
        if tab == .bookmarks {
            await loadBookmarks()
            return
        }

        guard !(tabIsLoading[tab] ?? false) else { return }
        tabIsLoading[tab] = true
        tabCursors[tab] = nil
        tabHasMore[tab] = true

        do {
            let response = try await fetchFeed(tab: tab, cursor: nil)
            tabFeeds[tab] = response.feed
            tabCursors[tab] = response.cursor
            tabHasMore[tab] = response.cursor != nil
            // 後方互換
            if tab == .posts { posts = response.feed; cursor = response.cursor; hasMore = response.cursor != nil }
        } catch {
            errorMessage = error.localizedDescription
        }
        tabIsLoading[tab] = false
    }

    @MainActor
    func loadMoreTab(_ tab: ProfileTab) async {
        // starterPacks / bookmarks タブはページネーションなし
        guard tab != .starterPacks, tab != .bookmarks else { return }
        guard !(tabIsLoading[tab] ?? false),
              tabHasMore[tab] ?? false,
              let currentCursor = tabCursors[tab] ?? nil else { return }
        tabIsLoading[tab] = true

        do {
            let response = try await fetchFeed(tab: tab, cursor: currentCursor)
            tabFeeds[tab]?.append(contentsOf: response.feed)
            tabCursors[tab] = response.cursor
            tabHasMore[tab] = response.cursor != nil
            if tab == .posts { posts = tabFeeds[tab] ?? []; cursor = response.cursor; hasMore = response.cursor != nil }
        } catch {
            errorMessage = error.localizedDescription
        }
        tabIsLoading[tab] = false
    }

    private func fetchFeed(tab: ProfileTab, cursor: String?) async throws -> TimelineResponse {
        switch tab {
        case .posts:
            return try await graphService.getAuthorFeed(actor: actor, limit: 30, cursor: cursor, filter: "posts_no_replies")
        case .replies:
            return try await graphService.getAuthorFeed(actor: actor, limit: 30, cursor: cursor, filter: "posts_with_replies")
        case .media:
            return try await graphService.getAuthorFeed(actor: actor, limit: 30, cursor: cursor, filter: "posts_with_media")
        case .likes:
            return try await graphService.getActorLikes(actor: actor, limit: 30, cursor: cursor)
        case .starterPacks, .bookmarks:
            // これらのタブは loadTab で分岐済みのため到達しない
            return TimelineResponse(feed: [], cursor: nil)
        }
    }

    // MARK: - ブックマーク一覧読み込み

    var bookmarkedPosts: [FeedViewPost] = []
    var isLoadingBookmarks = false

    @MainActor
    func loadBookmarks() async {
        guard let postService else {
            print("[ProfileViewModel] loadBookmarks: postService is nil")
            return
        }
        guard !isLoadingBookmarks else { return }
        isLoadingBookmarks = true
        do {
            let response = try await postService.getBookmarks()
            print("[ProfileViewModel] loadBookmarks: got \(response.bookmarks.count) bookmarks")
            bookmarkedPosts = response.bookmarks.compactMap { bookmark -> FeedViewPost? in
                guard let post = bookmark.item else { return nil }
                return FeedViewPost(post: post, reply: nil, reason: nil)
            }
        } catch {
            print("[ProfileViewModel] loadBookmarks error: \(error)")
            errorMessage = error.localizedDescription
        }
        isLoadingBookmarks = false
    }

    @MainActor
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        async let profileTask: () = refreshProfile()
        async let postsTask: () = refreshCurrentTab()
        _ = await (profileTask, postsTask)
        isRefreshing = false
    }

    private func refreshProfile() async {
        if let updated = try? await graphService.getProfile(actor: actor) {
            await MainActor.run { profile = updated }
        }
    }

    private func refreshCurrentTab() async {
        let tab = selectedTab
        switch tab {
        case .bookmarks:
            await MainActor.run { isLoadingBookmarks = false }
            await loadBookmarks()
        case .starterPacks:
            break
        default:
            if let response = try? await fetchFeed(tab: tab, cursor: nil) {
                await MainActor.run {
                    tabFeeds[tab] = response.feed
                    tabCursors[tab] = response.cursor
                    tabHasMore[tab] = response.cursor != nil
                    if tab == .posts { posts = response.feed; cursor = response.cursor; hasMore = response.cursor != nil }
                }
            }
        }
    }

    /// 投稿削除後に全タブのローカルリストから除去
    @MainActor
    func removePost(uri: String) {
        posts.removeAll { $0.post.uri == uri }
        for tab in ProfileTab.allCases {
            tabFeeds[tab]?.removeAll { $0.post.uri == uri }
        }
    }

    // MARK: - ピン留め投稿

    @MainActor
    func loadPinnedPost(postService: PostService) async {
        guard let uri = profile?.pinnedPost?.uri else { return }
        guard !isLoadingPinnedPost else { return }
        isLoadingPinnedPost = true
        if let posts = try? await postService.getPosts(uris: [uri]), let post = posts.first {
            pinnedPost = post
        }
        isLoadingPinnedPost = false
    }

    // MARK: - プロフィール内検索

    @MainActor
    func searchInProfile(query: String) async {
        guard let searchService else { return }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            profileSearchResults = []
            profileSearchCursor = nil
            profileSearchHasMore = false
            return
        }

        profileSearchTask?.cancel()
        profileSearchTask = Task {
            guard !Task.isCancelled else { return }
            isSearchingInProfile = true
            profileSearchCursor = nil
            profileSearchHasMore = false

            do {
                let response = try await searchService.searchPostsByAuthor(
                    query: trimmed,
                    author: actor,
                    limit: 25,
                    cursor: nil
                )
                guard !Task.isCancelled else { return }
                profileSearchResults = response.posts
                profileSearchCursor = response.cursor
                profileSearchHasMore = response.cursor != nil
            } catch {
                if !(error is CancellationError) {
                    errorMessage = error.localizedDescription
                }
            }
            isSearchingInProfile = false
        }
        await profileSearchTask?.value
    }

    @MainActor
    func loadMoreSearchResults() async {
        guard let searchService,
              !isSearchingInProfile,
              profileSearchHasMore,
              let cursor = profileSearchCursor else { return }
        let trimmed = profileSearchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isSearchingInProfile = true
        do {
            let response = try await searchService.searchPostsByAuthor(
                query: trimmed,
                author: actor,
                limit: 25,
                cursor: cursor
            )
            profileSearchResults.append(contentsOf: response.posts)
            profileSearchCursor = response.cursor
            profileSearchHasMore = response.cursor != nil
        } catch {
            if !(error is CancellationError) {
                errorMessage = error.localizedDescription
            }
        }
        isSearchingInProfile = false
    }

    // MARK: - フォロー / フォロー解除

    @MainActor
    func toggleFollow() async {
        guard !isFollowLoading, let profile = profile else { return }
        isFollowLoading = true

        let isCurrentlyFollowing = profile.viewer?.following != nil

        do {
            if isCurrentlyFollowing, let followUri = profile.viewer?.following {
                try await graphService.unfollow(followUri: followUri)
                // viewer を更新（フォロー解除）
                updateViewerFollowing(to: nil)
            } else {
                let ref = try await graphService.follow(did: profile.did)
                // viewer を更新（フォロー中）
                updateViewerFollowing(to: ref.uri)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isFollowLoading = false
    }

    @MainActor
    private func updateViewerFollowing(to uri: String?) {
        guard let current = profile else { return }
        let oldViewer = current.viewer
        let newViewer = ActorViewerState(
            muted: oldViewer?.muted,
            blockedBy: oldViewer?.blockedBy,
            blocking: oldViewer?.blocking,
            following: uri,
            followedBy: oldViewer?.followedBy
        )
        profile = ProfileView(
            did: current.did,
            handle: current.handle,
            displayName: current.displayName,
            description: current.description,
            avatar: current.avatar,
            banner: current.banner,
            followersCount: current.followersCount,
            followsCount: current.followsCount,
            postsCount: current.postsCount,
            viewer: newViewer,
            labels: current.labels,
            createdAt: current.createdAt,
            pinnedPost: current.pinnedPost,
            verification: current.verification
        )
    }

    // MARK: - ミュート

    @MainActor
    func toggleMute() async {
        guard !isMuteLoading, let profile = profile else { return }
        isMuteLoading = true
        let isMuted = profile.viewer?.muted == true
        do {
            if isMuted {
                try await graphService.unmuteActor(did: profile.did)
                updateViewerMuted(to: false)
            } else {
                try await graphService.muteActor(did: profile.did)
                updateViewerMuted(to: true)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isMuteLoading = false
    }

    @MainActor
    private func updateViewerMuted(to muted: Bool) {
        guard let current = profile else { return }
        let oldViewer = current.viewer
        let newViewer = ActorViewerState(
            muted: muted,
            blockedBy: oldViewer?.blockedBy,
            blocking: oldViewer?.blocking,
            following: oldViewer?.following,
            followedBy: oldViewer?.followedBy
        )
        profile = ProfileView(
            did: current.did, handle: current.handle,
            displayName: current.displayName, description: current.description,
            avatar: current.avatar, banner: current.banner,
            followersCount: current.followersCount, followsCount: current.followsCount,
            postsCount: current.postsCount, viewer: newViewer,
            labels: current.labels, createdAt: current.createdAt,
            pinnedPost: current.pinnedPost,
            verification: current.verification
        )
    }

    // MARK: - ブロック

    @MainActor
    func toggleBlock() async {
        guard !isBlockLoading, let profile = profile else { return }
        isBlockLoading = true
        let blockUri = profile.viewer?.blocking
        do {
            if let blockUri {
                try await graphService.unblockActor(blockUri: blockUri)
                updateViewerBlocking(to: nil)
            } else {
                let uri = try await graphService.blockActor(did: profile.did)
                updateViewerBlocking(to: uri)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isBlockLoading = false
    }

    @MainActor
    private func updateViewerBlocking(to blockUri: String?) {
        guard let current = profile else { return }
        let oldViewer = current.viewer
        let newViewer = ActorViewerState(
            muted: oldViewer?.muted,
            blockedBy: oldViewer?.blockedBy,
            blocking: blockUri,
            following: oldViewer?.following,
            followedBy: oldViewer?.followedBy
        )
        profile = ProfileView(
            did: current.did, handle: current.handle,
            displayName: current.displayName, description: current.description,
            avatar: current.avatar, banner: current.banner,
            followersCount: current.followersCount, followsCount: current.followsCount,
            postsCount: current.postsCount, viewer: newViewer,
            labels: current.labels, createdAt: current.createdAt,
            pinnedPost: current.pinnedPost,
            verification: current.verification
        )
    }
}
