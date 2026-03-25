// ProfileView.swift
// kazahana-ios
// プロフィール画面

import SwiftUI

struct ProfileScreenView: View {
    @Environment(AuthViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss
    let actor: String

    @State private var viewModel: ProfileViewModel?
    @State private var selectedPost: FeedViewPost?
    @State private var selectedAuthorDID: IdentifiableString? = nil
    @State private var userListType: UserListType? = nil
    @State private var selectedList: GraphListView? = nil
    @State private var selectedFeed: GeneratorView? = nil
    @State private var selectedStarterPack: StarterPackViewBasic? = nil
    @State private var showSettings = false
    @State private var showCompose = false
    @State private var mentionInitialText: IdentifiableString? = nil
    @State private var quotePost: PostView? = nil
    @State private var replyToPost: PostView? = nil
    /// コンパクトヘッダー表示フラグ（スクロール開始後に true）
    @State private var showCompact: Bool = false

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
            // プロフィールロード後にピン留め投稿を取得
            if let vm = viewModel {
                await vm.loadPinnedPost(postService: PostService(client: authVM.client))
            }
        }
        .navigationDestination(item: $selectedPost) { post in
            ThreadView(uri: post.post.uri, postService: PostService(client: authVM.client))
                .environment(authVM)
        }
        .navigationDestination(item: $selectedAuthorDID) { item in
            ProfileScreenView(actor: item.value)
                .environment(authVM)
        }
        .navigationDestination(item: $userListType) { listType in
            UserListView(listType: listType)
                .environment(authVM)
        }
        .navigationDestination(item: $selectedList) { list in
            ListFeedView(list: list)
                .environment(authVM)
        }
        .navigationDestination(item: $selectedFeed) { feed in
            FeedGeneratorFeedView(feed: feed)
                .environment(authVM)
        }
        .navigationDestination(item: $selectedStarterPack) { pack in
            StarterPackDetailView(uri: pack.uri)
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
        .sheet(item: $mentionInitialText) { item in
            // 他人のプロフィール画面から @mention 付きで投稿
            ComposeView(postService: PostService(client: authVM.client), initialText: item.value)
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
        .enableInteractivePop()
    }

    private func setupViewModel() {
        guard viewModel == nil else { return }
        let graphService = GraphService(client: authVM.client)
        let searchService = SearchService(client: authVM.client)
        let feedService = FeedService(client: authVM.client)
        let postService = PostService(client: authVM.client)
        viewModel = ProfileViewModel(actor: actor, graphService: graphService, searchService: searchService, feedService: feedService, postService: postService)
    }

    @ViewBuilder
    private func profileContent(vm: ProfileViewModel) -> some View {
        let isSelf = authVM.client.currentSession?.did == actor

        ZStack(alignment: .top) {
            // ── スクロールエリア ────────────────────────────
            ScrollView {
                LazyVStack(spacing: 0) {
                    // バナー＋フルプロフィール情報（スクロールで流れる）
                    ProfileHeaderView(
                        vm: vm,
                        isSelf: isSelf,
                        onTapFollowers: { userListType = .followers(actor: actor) },
                        onTapFollowing: { userListType = .following(actor: actor) },
                        onTapSettings: { showSettings = true }
                    )

                    // タブバー（ScrollView内・スクロールで流れる位置に配置）
                    VStack(spacing: 0) {
                        Divider()
                        profileTabBar(vm: vm)
                        Divider()
                    }
                    .background(Color(.systemBackground))

                    // プロフィール内検索バー
                    profileSearchBar(vm: vm)

                    // 検索中は検索結果を表示、それ以外はタブフィード
                    if !vm.profileSearchQuery.isEmpty {
                        profileSearchResults(vm: vm)
                    } else if vm.selectedTab == .feeds {
                        profileFeedsTab(vm: vm)
                    } else if vm.selectedTab == .lists {
                        profileListsTab(vm: vm)
                    } else if vm.selectedTab == .starterPacks {
                        StarterPackListTabView(actor: actor, onSelect: { pack in
                            selectedStarterPack = pack
                        })
                        .environment(authVM)
                    } else if vm.selectedTab == .bookmarks {
                        bookmarksTab(vm: vm)
                    } else {
                        // ピン留め投稿（投稿タブのみ）
                        if vm.selectedTab == .posts, let pinned = vm.pinnedPost {
                            pinnedPostView(post: pinned, vm: vm)
                            Divider().padding(.leading, 16)
                        }

                        // タブ別フィード
                        let feed = vm.currentFeed
                        if vm.isCurrentTabLoading && feed.isEmpty {
                            ProgressView()
                                .padding(.top, 32)
                        } else if feed.isEmpty && !vm.isCurrentTabLoading {
                            Text(String(localized: "profile.noPosts"))
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
                                    onTapAuthor: { did in selectedAuthorDID = IdentifiableString(did) },
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

                    // 最下部の余白（画面高の50%）— 最後のアイテムをタップしやすくする
                    Color.clear
                        .containerRelativeFrame(.vertical) { size, _ in size * 0.5 }
                }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                // contentInsets.top はセーフエリア等の自動インセットを除いた位置
                geometry.contentOffset.y > geometry.contentInsets.top + 160
            } action: { _, isScrolled in
                withAnimation(.easeInOut(duration: 0.15)) {
                    showCompact = isScrolled
                }
            }
            .refreshable {
                // プルリフレッシュ時はコンパクトヘッダーをリセット（ScrollViewがトップに戻るので自動的に showCompact = false になるが念のため）
                await vm.refresh()
            }

            // ── 固定エリア（スクロール後だけ最前面に表示）──────
            if showCompact {
                VStack(spacing: 0) {
                    compactHeader(vm: vm, isSelf: isSelf)
                    Divider()
                    profileTabBar(vm: vm)
                    Divider()
                }
                .background(Color(.systemBackground))
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                // 他人のプロフィール画面では @handle を初期テキストとして挿入
                if !isSelf, let handle = vm.profile?.handle {
                    mentionInitialText = IdentifiableString("@\(handle) ")
                } else {
                    showCompose = true
                }
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
        .overlay(alignment: .topLeading) {
            if !isSelf {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.leading, 16)
                .padding(.top, 8)
            }
        }
    }

    /// スクロール後に固定されるコンパクトヘッダー（アバター小＋名前＋設定ボタン）
    private func compactHeader(vm: ProfileViewModel, isSelf: Bool) -> some View {
        HStack(spacing: 12) {
            AvatarView(
                url: vm.profile?.avatar,
                size: 36,
                showSupporterBadge: isSelf && AppSettings.shared.isSupporterBadgeActive
            )

            VStack(alignment: .leading, spacing: 1) {
                if let profile = vm.profile {
                    HStack(spacing: 4) {
                        Text(profile.displayNameOrHandle)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        if isBotAccount(did: profile.did, labels: profile.labels) {
                            BotBadge(size: 18)
                        }
                    }
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

    @ViewBuilder
    private func pinnedPostView(post: PostView, vm: ProfileViewModel) -> some View {
        let feedPost = FeedViewPost(post: post, reply: nil, reason: nil)
        VStack(spacing: 0) {
            // ピン留めラベル（リポスト理由行と同じ構造）
            HStack(spacing: 4) {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                Text(String(localized: "post.pinned"))
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            PostCardView(
                feedPost: feedPost,
                postService: PostService(client: authVM.client),
                onTapPost: { _ in selectedPost = feedPost },
                onTapAuthor: { did in selectedAuthorDID = IdentifiableString(did) },
                onTapReply: { p in replyToPost = p },
                onTapQuote: { p in quotePost = p },
                onDelete: { p in vm.removePost(uri: p.uri) },
                currentUserDID: authVM.client.currentSession?.did
            )
        }
    }

    @ViewBuilder
    private func profileSearchBar(vm: ProfileViewModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField(String(localized: "profile.searchPlaceholder"), text: Binding(
                get: { vm.profileSearchQuery },
                set: { vm.profileSearchQuery = $0 }
            ))
            .font(.subheadline)
            .submitLabel(.search)
            .onSubmit {
                Task { await vm.searchInProfile(query: vm.profileSearchQuery) }
            }
            .onChange(of: vm.profileSearchQuery) { _, newValue in
                if newValue.isEmpty {
                    vm.profileSearchResults = []
                    vm.profileSearchCursor = nil
                    vm.profileSearchHasMore = false
                }
            }
            if !vm.profileSearchQuery.isEmpty {
                Button {
                    vm.profileSearchQuery = ""
                    vm.profileSearchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func profileSearchResults(vm: ProfileViewModel) -> some View {
        if vm.isSearchingInProfile && vm.profileSearchResults.isEmpty {
            ProgressView().padding(.top, 32)
        } else if vm.profileSearchResults.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(String(format: String(localized: "search.noResults"), vm.profileSearchQuery))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)
            .frame(maxWidth: .infinity)
        } else {
            ForEach(vm.profileSearchResults, id: \.uri) { post in
                let feedPost = FeedViewPost(post: post, reply: nil, reason: nil)
                PostCardView(
                    feedPost: feedPost,
                    postService: PostService(client: authVM.client),
                    onTapPost: { _ in selectedPost = feedPost },
                    onTapAuthor: { did in selectedAuthorDID = IdentifiableString(did) },
                    onTapReply: { p in replyToPost = p },
                    onTapQuote: { p in quotePost = p },
                    currentUserDID: authVM.client.currentSession?.did
                )
                Divider().padding(.leading, 16)
                if post.uri == vm.profileSearchResults.last?.uri {
                    Color.clear
                        .frame(height: 1)
                        .task { await vm.loadMoreSearchResults() }
                }
            }
            if vm.isSearchingInProfile {
                ProgressView().padding()
            }
        }
    }

    @ViewBuilder
    private func profileFeedsTab(vm: ProfileViewModel) -> some View {
        if vm.isLoadingFeeds && vm.actorFeeds.isEmpty {
            ProgressView().padding(.top, 32)
        } else if vm.actorFeeds.isEmpty {
            Text(String(localized: "profile.noFeeds"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 40)
                .frame(maxWidth: .infinity)
        } else {
            ForEach(vm.actorFeeds) { feed in
                Button {
                    selectedFeed = feed
                } label: {
                    HStack(spacing: 12) {
                        if let avatarURL = feed.avatar, let url = URL(string: avatarURL) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color.gray.opacity(0.3)
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Image(systemName: "list.star")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                                .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feed.displayName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if let desc = feed.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            if let likes = feed.likeCount {
                                Label("\(likes)", systemImage: "heart")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 16)
            }
        }
    }

    @ViewBuilder
    private func bookmarksTab(vm: ProfileViewModel) -> some View {
        if vm.isLoadingBookmarks && vm.bookmarkedPosts.isEmpty {
            ProgressView().padding(.top, 32)
        } else if vm.bookmarkedPosts.isEmpty {
            Text(String(localized: "profile.noBookmarks"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 40)
                .frame(maxWidth: .infinity)
        } else {
            ForEach(vm.bookmarkedPosts) { feedPost in
                PostCardView(
                    feedPost: feedPost,
                    postService: PostService(client: authVM.client),
                    onTapPost: { _ in selectedPost = feedPost },
                    onTapAuthor: { did in selectedAuthorDID = IdentifiableString(did) },
                    onTapReply: { post in replyToPost = post },
                    onTapQuote: { post in quotePost = post },
                    onUnbookmark: { _ in
                        vm.bookmarkedPosts.removeAll { $0.post.uri == feedPost.post.uri }
                    },
                    currentUserDID: authVM.client.currentSession?.did
                )
                Divider().padding(.leading, 16)
            }
        }
    }

    @ViewBuilder
    private func profileListsTab(vm: ProfileViewModel) -> some View {
        if vm.isLoadingLists && vm.actorLists.isEmpty {
            ProgressView().padding(.top, 32)
        } else if vm.actorLists.isEmpty {
            Text(String(localized: "profile.noLists"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 40)
                .frame(maxWidth: .infinity)
        } else {
            ForEach(vm.actorLists) { list in
                Button {
                    selectedList = list
                } label: {
                    HStack(spacing: 12) {
                        if let avatarURL = list.avatar, let url = URL(string: avatarURL) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color.gray.opacity(0.3)
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                                .background(Color(.systemGray5), in: Circle())
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(list.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if let desc = list.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            if let count = list.listItemCount {
                                Label("\(count)", systemImage: "person.2")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 16)
            }
        }
    }

    private func profileTabBar(vm: ProfileViewModel) -> some View {
        let isSelf = authVM.client.currentSession?.did == actor
        let visibleTabs = ProfileTab.allCases.filter { $0 != .bookmarks || isSelf }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(visibleTabs, id: \.self) { tab in
                    Button {
                        if vm.selectedTab != tab {
                            vm.selectedTab = tab
                            // feeds/lists タブは専用フラグ、それ以外は tabFeeds で判断
                            let needsLoad: Bool = {
                                switch tab {
                                case .feeds:        return vm.actorFeeds.isEmpty && !vm.isLoadingFeeds
                                case .lists:        return vm.actorLists.isEmpty && !vm.isLoadingLists
                                case .starterPacks: return false  // StarterPackListTabView が自前でロード
                                case .bookmarks:    return vm.bookmarkedPosts.isEmpty && !vm.isLoadingBookmarks
                                default:            return vm.tabFeeds[tab]?.isEmpty ?? true
                                }
                            }()
                            if needsLoad {
                                Task { await vm.loadTab(tab) }
                            }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(tab.displayName)
                                .font(.subheadline)
                                .fontWeight(vm.selectedTab == tab ? .semibold : .regular)
                                .foregroundStyle(vm.selectedTab == tab ? Color.primary : Color.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 10)
                            Rectangle()
                                .fill(vm.selectedTab == tab ? Color.accentColor : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
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

            // アバター + フォロー/設定ボタン（アバターと同じ高さの行）
            HStack(alignment: .bottom) {
                AvatarView(
                    url: vm.profile?.avatar,
                    size: 72,
                    showSupporterBadge: isSelf && AppSettings.shared.isSupporterBadgeActive
                )
                .padding(4)
                .background(Color(.systemBackground), in: Circle())
                .offset(y: -36)
                .padding(.leading, 16)

                Spacer()

                if isSelf {
                    Button {
                        onTapSettings?()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(Color(.systemGray5), in: Circle())
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                } else {
                    followButton
                        .padding(.trailing, 16)
                        .padding(.top, 8)
                }
            }
            .padding(.bottom, -24)

            // 表示名 + ハンドル
            VStack(alignment: .leading, spacing: 4) {
                if let profile = vm.profile {
                    HStack(spacing: 6) {
                        Text(profile.displayNameOrHandle)
                            .font(.title3)
                            .fontWeight(.bold)
                        if isBotAccount(did: profile.did, labels: profile.labels) {
                            BotBadge(size: 18)
                        }
                    }
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
                                statItem(count: followers, label: String(localized: "profile.followers"))
                            }
                            .buttonStyle(.plain)
                        }
                        if let follows = profile.followsCount {
                            Button { onTapFollowing?() } label: {
                                statItem(count: follows, label: String(localized: "profile.following"))
                            }
                            .buttonStyle(.plain)
                        }
                        if let posts = profile.postsCount {
                            statItem(count: posts, label: String(localized: "profile.posts"))
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
                    Text(isFollowing ? String(localized: "profile.following") : String(localized: "profile.follow"))
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


