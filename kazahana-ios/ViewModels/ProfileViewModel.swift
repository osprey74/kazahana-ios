// ProfileViewModel.swift
// kazahana-ios
// プロフィール画面の ViewModel

import Foundation
import Observation

@Observable
final class ProfileViewModel {
    var profile: ProfileView?
    var posts: [FeedViewPost] = []
    var isLoadingProfile = false
    var isLoadingPosts = false
    var isRefreshing = false
    var isFollowLoading = false
    var errorMessage: String?

    private var cursor: String?
    private var hasMore = true
    let actor: String

    private let graphService: GraphService

    init(actor: String, graphService: GraphService) {
        self.actor = actor
        self.graphService = graphService
    }

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

    // MARK: - 投稿一覧読み込み

    @MainActor
    func loadPosts() async {
        guard !isLoadingPosts else { return }
        isLoadingPosts = true
        cursor = nil
        hasMore = true

        do {
            let response = try await graphService.getAuthorFeed(actor: actor, limit: 30)
            posts = response.feed
            cursor = response.cursor
            hasMore = response.cursor != nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingPosts = false
    }

    @MainActor
    func loadMorePosts() async {
        guard !isLoadingPosts, hasMore, let currentCursor = cursor else { return }
        isLoadingPosts = true

        do {
            let response = try await graphService.getAuthorFeed(actor: actor, limit: 30, cursor: currentCursor)
            posts.append(contentsOf: response.feed)
            cursor = response.cursor
            hasMore = response.cursor != nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingPosts = false
    }

    @MainActor
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        async let profileTask: () = refreshProfile()
        async let postsTask: () = refreshPosts()
        _ = await (profileTask, postsTask)
        isRefreshing = false
    }

    private func refreshProfile() async {
        if let updated = try? await graphService.getProfile(actor: actor) {
            await MainActor.run { profile = updated }
        }
    }

    private func refreshPosts() async {
        if let response = try? await graphService.getAuthorFeed(actor: actor, limit: 30) {
            await MainActor.run {
                posts = response.feed
                cursor = response.cursor
                hasMore = response.cursor != nil
            }
        }
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
            createdAt: current.createdAt
        )
    }
}
