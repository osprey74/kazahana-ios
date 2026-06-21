// ProfileView.swift
// kazahana-ios
// プロフィール画面

import SwiftUI

struct ProfileScreenView: View {
    @Environment(AuthViewModel.self) private var authVM
    @Environment(EvacuationViewModel.self) private var evacuationVM: EvacuationViewModel?
    @Environment(\.dismiss) private var dismiss
    let actor: String

    @State private var viewModel: ProfileViewModel?
    @State private var selectedPost: FeedViewPost?
    @State private var selectedAuthorDID: IdentifiableString? = nil
    @State private var userListType: UserListType? = nil
    @State private var selectedStarterPack: StarterPackViewBasic? = nil
    @State private var showSettings = false
    @State private var showCompose = false
    @State private var mentionInitialText: IdentifiableString? = nil
    @State private var quotePost: PostView? = nil
    @State private var replyToPost: PostView? = nil
    @State private var showAddToList = false
    @State private var showQRSheet = false
    @State private var showMuteConfirm = false
    @State private var showBlockConfirm = false
    @State private var reportTarget: ReportTarget? = nil
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
        .sheet(isPresented: $showQRSheet) {
            if let profile = viewModel?.profile {
                ProfileQRSheet(
                    handle: profile.handle,
                    displayName: profile.displayNameOrHandle
                )
            }
        }
        .sheet(isPresented: $showAddToList) {
            if viewModel != nil {
                AddToListView(
                    targetDid: actor,
                    graphService: GraphService(client: authVM.client)
                )
                .environment(authVM)
            }
        }
        .sheet(item: $reportTarget) { target in
            ReportView(target: target, postService: PostService(client: authVM.client))
        }
        .confirmationDialog(
            viewModel?.profile?.viewer?.muted == true
                ? String(localized: "profile.unmuteConfirmTitle")
                : String(localized: "profile.muteConfirmTitle"),
            isPresented: $showMuteConfirm,
            titleVisibility: .visible
        ) {
            Button(
                viewModel?.profile?.viewer?.muted == true
                    ? String(localized: "profile.unmute")
                    : String(localized: "profile.mute"),
                role: viewModel?.profile?.viewer?.muted == true ? .none : .destructive
            ) {
                Task { await viewModel?.toggleMute() }
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
        .confirmationDialog(
            viewModel?.profile?.viewer?.blocking != nil
                ? String(localized: "profile.unblockConfirmTitle")
                : String(localized: "profile.blockConfirmTitle"),
            isPresented: $showBlockConfirm,
            titleVisibility: .visible
        ) {
            Button(
                viewModel?.profile?.viewer?.blocking != nil
                    ? String(localized: "profile.unblock")
                    : String(localized: "profile.block"),
                role: viewModel?.profile?.viewer?.blocking != nil ? .none : .destructive
            ) {
                Task { await viewModel?.toggleBlock() }
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
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
                        onTapSettings: { showSettings = true },
                        onTapQR: { showQRSheet = true },
                        onTapMute: { showMuteConfirm = true },
                        onTapBlock: { showBlockConfirm = true },
                        onTapAddToList: { showAddToList = true },
                        onTapReport: { reportTarget = .account(did: actor) }
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
            .padding(.bottom, evacuationVM?.bannerVisible == true ? 94 : 24)
            .animation(.easeInOut(duration: 0.3), value: evacuationVM?.bannerVisible)
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
                        VerificationBadge(profile: profile, size: 18)
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
                #if !targetEnvironment(macCatalyst)
                Button {
                    showQRSheet = true
                } label: {
                    Image(systemName: "qrcode")
                        .font(.system(size: 18))
                        .foregroundStyle(.primary)
                }
                #endif
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

    private func profileTabBar(vm: ProfileViewModel) -> some View {
        let isSelf = authVM.client.currentSession?.did == actor
        let visibleTabs = ProfileTab.allCases.filter { $0 != .bookmarks || isSelf }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(visibleTabs, id: \.self) { tab in
                    Button {
                        if vm.selectedTab != tab {
                            vm.selectedTab = tab
                            let needsLoad: Bool = {
                                switch tab {
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
    var onTapQR: (() -> Void)? = nil
    var onTapMute: (() -> Void)? = nil
    var onTapBlock: (() -> Void)? = nil
    var onTapAddToList: (() -> Void)? = nil
    var onTapReport: (() -> Void)? = nil

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
                    HStack(spacing: 8) {
                        #if !targetEnvironment(macCatalyst)
                        Button {
                            onTapQR?()
                        } label: {
                            Image(systemName: "qrcode")
                                .font(.system(size: 18))
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                                .background(Color(.systemGray5), in: Circle())
                        }
                        #endif
                        Button {
                            onTapSettings?()
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 18))
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                                .background(Color(.systemGray5), in: Circle())
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                } else {
                    HStack(spacing: 8) {
                        followButton
                        moreMenu
                    }
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
                        VerificationBadge(profile: profile, size: 18)
                        if isBotAccount(did: profile.did, labels: profile.labels) {
                            BotBadge(size: 18)
                        }
                    }
                    Text("@\(profile.handle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let bio = profile.description, !bio.isEmpty {
                        Text(Self.profileBioAttributedString(bio))
                            .font(.subheadline)
                            .padding(.top, 4)
                            .environment(\.openURL, OpenURLAction { url in
                                if url.scheme == "kazahana" {
                                    NotificationCenter.default.post(
                                        name: .kazahanaDeepLink,
                                        object: nil,
                                        userInfo: ["url": url]
                                    )
                                    return .handled
                                }
                                return .systemAction
                            })
                    }

                    // 統計（フォロー中・フォロワーはタップでリスト表示）
                    HStack(spacing: 16) {
                        if let follows = profile.followsCount {
                            Button { onTapFollowing?() } label: {
                                statItem(count: follows, label: String(localized: "profile.following"))
                            }
                            .buttonStyle(.plain)
                        }
                        if let followers = profile.followersCount {
                            Button { onTapFollowers?() } label: {
                                statItem(count: followers, label: String(localized: "profile.followers"))
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

    @ViewBuilder
    private var moreMenu: some View {
        if let profile = vm.profile {
            let isMuted = profile.viewer?.muted == true
            let isBlocked = profile.viewer?.blocking != nil

            Menu {
                Button {
                    onTapAddToList?()
                } label: {
                    Label(String(localized: "profile.addToList"), systemImage: "list.bullet.rectangle.portrait")
                }

                Divider()

                Button {
                    onTapMute?()
                } label: {
                    if vm.isMuteLoading {
                        Label(String(localized: "profile.muteUser"), systemImage: "ellipsis")
                    } else if isMuted {
                        Label(String(localized: "profile.unmuteUser"), systemImage: "speaker.wave.2")
                    } else {
                        Label(String(localized: "profile.muteUser"), systemImage: "speaker.slash")
                    }
                }
                .disabled(vm.isMuteLoading)

                Button(role: isBlocked ? .none : .destructive) {
                    onTapBlock?()
                } label: {
                    if vm.isBlockLoading {
                        Label(String(localized: "profile.blockUser"), systemImage: "ellipsis")
                    } else if isBlocked {
                        Label(String(localized: "profile.unblockUser"), systemImage: "hand.raised.slash")
                    } else {
                        Label(String(localized: "profile.blockUser"), systemImage: "hand.raised")
                    }
                }
                .disabled(vm.isBlockLoading)

                Button(role: .destructive) {
                    onTapReport?()
                } label: {
                    Label(String(localized: "profile.reportUser"), systemImage: "flag")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color(.systemGray5), in: Circle())
            }
        }
    }

    /// プロフィール説明文からリンク・メンション・ハッシュタグを検出して AttributedString を生成
    /// プロフィールには facets が付与されないため、クライアント側で自動検出する
    static func profileBioAttributedString(_ text: String) -> AttributedString {
        let detected = RichTextParser.detectFacets(in: text)
        let facets = RichTextParser.buildFacets(from: detected, resolvedMentions: [:])
        // メンションは DID 未解決のため除外されるが、URL とハッシュタグは有効化される
        if facets.isEmpty {
            return AttributedString(text)
        }
        return RichTextParser.attributedString(text: text, facets: facets)
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


