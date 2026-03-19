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
    @State private var showSettings = false
    @State private var showCompose = false
    @State private var quotePost: PostView? = nil
    @State private var replyToPost: PostView? = nil
    /// スクロール量（0 = 最上部）
    @State private var scrollOffset: CGFloat = 0

    /// コンパクトヘッダー表示フラグ（少しでもスクロールしたら表示）
    private var showCompact: Bool { scrollOffset > 8 }

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
                group.addTask { await viewModel?.loadTab(.posts) }
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
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(authVM)
                .environment(AppSettings.shared)
        }
        .sheet(isPresented: $showCompose) {
            ComposeView(postService: PostService(client: authVM.client))
                .environment(AppSettings.shared)
        }
        .sheet(item: $quotePost) { quoted in
            ComposeView(postService: PostService(client: authVM.client), quotedPost: quoted)
                .environment(AppSettings.shared)
        }
        .sheet(item: $replyToPost) { replyTo in
            ComposeView(postService: PostService(client: authVM.client), replyTo: replyTo)
                .environment(AppSettings.shared)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func setupViewModel() {
        guard viewModel == nil else { return }
        let graphService = GraphService(client: authVM.client)
        viewModel = ProfileViewModel(actor: actor, graphService: graphService)
    }

    @ViewBuilder
    private func profileContent(vm: ProfileViewModel) -> some View {
        let isSelf = authVM.client.currentSession?.did == actor

        VStack(spacing: 0) {
            // ── 固定エリア（ScrollViewの外側）──────────────────
            VStack(spacing: 0) {
                // コンパクトヘッダー：スクロール開始後に表示
                if showCompact {
                    compactHeader(vm: vm, isSelf: isSelf)
                        .transition(.opacity)
                }
                Divider()
                profileTabBar(vm: vm)
                Divider()
            }
            .background(Color(.systemBackground))
            .animation(.easeInOut(duration: 0.15), value: showCompact)

            // ── スクロールエリア ────────────────────────────
            ScrollView {
                // offset 検知アンカー
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: -geo.frame(in: .named("profileScroll")).minY
                    )
                }
                .frame(height: 0)

                LazyVStack(spacing: 0) {
                    // バナー＋フルプロフィール情報（スクロールで流れる）
                    ProfileHeaderView(
                        vm: vm,
                        isSelf: isSelf,
                        onTapFollowers: { userListType = .followers(actor: actor) },
                        onTapFollowing: { userListType = .following(actor: actor) },
                        onTapSettings: { showSettings = true }
                    )

                    Divider()

                    // タブ別フィード
                    let feed = vm.currentFeed
                    if vm.isCurrentTabLoading && feed.isEmpty {
                        ProgressView()
                            .padding(.top, 32)
                    } else if feed.isEmpty && !vm.isCurrentTabLoading {
                        Text("投稿がありません")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(feed) { feedPost in
                            PostCardView(
                                feedPost: feedPost,
                                postService: PostService(client: authVM.client),
                                onTapPost: { _ in selectedPost = feedPost },
                                onTapReply: { post in replyToPost = post },
                                onTapQuote: { post in quotePost = post },
                                onDelete: { post in vm.removePost(uri: post.uri) },
                                currentUserDID: authVM.client.currentSession?.did
                            )
                            Divider().padding(.leading, 16)
                            if feedPost.post.uri == feed.last?.post.uri {
                                Color.clear
                                    .frame(height: 1)
                                    .task { await vm.loadMoreTab(vm.selectedTab) }
                            }
                        }
                        if vm.isCurrentTabLoading {
                            ProgressView().padding()
                        }
                    }
                }
            }
            .coordinateSpace(name: "profileScroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                scrollOffset = offset
            }
            .refreshable {
                await vm.refresh()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                showCompose = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.accentColor, in: Circle())
                    .shadow(radius: 4, y: 2)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 24)
        }
    }

    /// スクロール後に固定されるコンパクトヘッダー（アバター小＋名前＋設定ボタン）
    private func compactHeader(vm: ProfileViewModel, isSelf: Bool) -> some View {
        HStack(spacing: 12) {
            AvatarView(url: vm.profile?.avatar, size: 36)

            VStack(alignment: .leading, spacing: 1) {
                if let profile = vm.profile {
                    Text(profile.displayNameOrHandle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text("@\(profile.handle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isSelf {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18))
                        .foregroundStyle(.primary)
                }
                .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func profileTabBar(vm: ProfileViewModel) -> some View {
        HStack(spacing: 0) {
            ForEach(ProfileTab.allCases, id: \.self) { tab in
                Button {
                    if vm.selectedTab != tab {
                        vm.selectedTab = tab
                        if vm.tabFeeds[tab]?.isEmpty ?? true {
                            Task { await vm.loadTab(tab) }
                        }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(tab.rawValue)
                            .font(.subheadline)
                            .fontWeight(vm.selectedTab == tab ? .semibold : .regular)
                            .foregroundStyle(vm.selectedTab == tab ? Color.primary : Color.secondary)
                            .padding(.vertical, 10)
                        Rectangle()
                            .fill(vm.selectedTab == tab ? Color.accentColor : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - プロフィールヘッダー（フル表示）

struct ProfileHeaderView: View {
    let vm: ProfileViewModel
    var isSelf: Bool = false
    var onTapFollowers: (() -> Void)? = nil
    var onTapFollowing: (() -> Void)? = nil
    var onTapSettings: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // バナー（自分のプロフィールの場合のみ右上に設定ボタンをオーバーレイ）
            ZStack(alignment: .topTrailing) {
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

                if isSelf {
                    Button {
                        onTapSettings?()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.black.opacity(0.35), in: Circle())
                    }
                    .padding(.top, 12)
                    .padding(.trailing, 16)
                }
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

// MARK: - ScrollView offset 検知用 PreferenceKey

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
