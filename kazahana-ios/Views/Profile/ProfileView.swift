// ProfileView.swift
// kazahana-ios
// プロフィール画面

import SwiftUI

struct ProfileScreenView: View {
    @Environment(AuthViewModel.self) private var authVM
    let actor: String

    @State private var viewModel: ProfileViewModel?
    @State private var selectedPost: FeedViewPost?
    @State private var userListType: UserListType? = nil

    var body: some View {
        Group {
            if let vm = viewModel {
                profileContent(vm: vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            setupViewModel()
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await viewModel?.loadProfile() }
                group.addTask { await viewModel?.loadPosts() }
            }
        }
        .navigationDestination(item: $selectedPost) { post in
            ThreadView(uri: post.post.uri, postService: PostService(client: authVM.client))
                .environment(authVM)
        }
        .navigationDestination(item: $userListType) { listType in
            UserListView(listType: listType)
                .environment(authVM)
        }
        .toolbar {
            // 自分のプロフィールの場合のみログアウトボタンを表示
            if authVM.client.currentSession?.did == actor {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        Task { await authVM.logout() }
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
        }
    }

    private func setupViewModel() {
        guard viewModel == nil else { return }
        let graphService = GraphService(client: authVM.client)
        viewModel = ProfileViewModel(actor: actor, graphService: graphService)
    }

    @ViewBuilder
    private func profileContent(vm: ProfileViewModel) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ProfileHeaderView(
                    vm: vm,
                    isSelf: authVM.client.currentSession?.did == actor,
                    onTapFollowers: { userListType = .followers(actor: actor) },
                    onTapFollowing: { userListType = .following(actor: actor) }
                )
                .padding(.bottom, 8)

                Divider()

                if vm.isLoadingPosts && vm.posts.isEmpty {
                    ProgressView()
                        .padding(.top, 32)
                } else {
                    ForEach(vm.posts) { feedPost in
                        PostCardView(
                            feedPost: feedPost,
                            postService: PostService(client: authVM.client),
                            onTapPost: { _ in selectedPost = feedPost }
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        Divider()
                            .padding(.leading, 16)
                        // Load more trigger
                        if feedPost.post.uri == vm.posts.last?.post.uri {
                            Color.clear
                                .frame(height: 1)
                                .task { await vm.loadMorePosts() }
                        }
                    }
                    if vm.isLoadingPosts {
                        ProgressView().padding()
                    }
                }
            }
        }
        .refreshable {
            await vm.refresh()
        }
    }
}

// MARK: - プロフィールヘッダー

struct ProfileHeaderView: View {
    let vm: ProfileViewModel
    var isSelf: Bool = false
    var onTapFollowers: (() -> Void)? = nil
    var onTapFollowing: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // バナー
            if let bannerURL = vm.profile?.banner, let url = URL(string: bannerURL) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(height: 120)
                .clipped()
            } else {
                Color.gray.opacity(0.2)
                    .frame(height: 120)
            }

            // アバター + フォローボタン
            HStack(alignment: .bottom) {
                AvatarView(url: vm.profile?.avatar, size: 72)
                    .padding(4)
                    .background(Color(.systemBackground), in: Circle())
                    .offset(y: -36)
                    .padding(.leading, 16)

                Spacer()

                if !isSelf {
                    followButton
                        .padding(.trailing, 16)
                        .padding(.top, 8)
                }
            }
            .padding(.bottom, -24)

            // 表示名 + ハンドル
            VStack(alignment: .leading, spacing: 4) {
                if let profile = vm.profile {
                    Text(profile.displayNameOrHandle)
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("@\(profile.handle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let bio = profile.description, !bio.isEmpty {
                        Text(bio)
                            .font(.subheadline)
                            .padding(.top, 4)
                    }

                    // 統計（フォロワー・フォロー中はタップでリスト表示）
                    HStack(spacing: 16) {
                        if let followers = profile.followersCount {
                            Button { onTapFollowers?() } label: {
                                statItem(count: followers, label: "フォロワー")
                            }
                            .buttonStyle(.plain)
                        }
                        if let follows = profile.followsCount {
                            Button { onTapFollowing?() } label: {
                                statItem(count: follows, label: "フォロー中")
                            }
                            .buttonStyle(.plain)
                        }
                        if let posts = profile.postsCount {
                            statItem(count: posts, label: "投稿")
                        }
                    }
                    .padding(.top, 8)
                } else if vm.isLoadingProfile {
                    ProgressView()
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private var followButton: some View {
        if let profile = vm.profile {
            let isFollowing = profile.viewer?.following != nil

            Button {
                Task { await vm.toggleFollow() }
            } label: {
                if vm.isFollowLoading {
                    ProgressView()
                        .frame(width: 80, height: 32)
                } else {
                    Text(isFollowing ? "フォロー中" : "フォロー")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(isFollowing ? Color.primary : Color.white)
                        .frame(width: 100, height: 32)
                        .background(isFollowing ? Color(.systemGray5) : .blue, in: Capsule())
                        .overlay(
                            Capsule().stroke(isFollowing ? Color(.systemGray3) : .clear, lineWidth: 1)
                        )
                }
            }
            .disabled(vm.isFollowLoading)
        }
    }

    private func statItem(count: Int, label: String) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
