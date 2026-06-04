// TimelineView.swift
// kazahana-ios
// ホームタイムライン画面（FAB・スレッド遷移・インタラクション対応）

import SwiftUI

struct TimelineView: View {

    @Environment(AuthViewModel.self) private var authVM
    @Environment(AppSettings.self) private var settings
    @Environment(EvacuationViewModel.self) private var evacuationVM: EvacuationViewModel?
    @State private var viewModel: TimelineViewModel
    @State private var showCompose: Bool = false
    @State private var replyToPost: PostView? = nil
    @State private var quotePost: PostView? = nil
    @State private var showFeedSelector: Bool = false
    @State private var showAccountSwitcher: Bool = false
    @State private var selectedPost: FeedViewPost? = nil
    @State private var selectedAuthorDID: IdentifiableString? = nil
    @State private var postActorListType: PostActorListType? = nil
    /// postList の ScrollViewProxy（スクロール先頭制御用）
    @State private var listScrollProxy: ScrollViewProxy? = nil
    /// 引用一覧遷移先 URI
    @State private var quotesPostURI: IdentifiableString? = nil
    /// ミュート/ブロック対象の投稿（確認ダイアログ用）
    @State private var muteTargetPost: PostView? = nil
    @State private var blockTargetPost: PostView? = nil

    private let postService: PostService

    init(client: ATProtoClient) {
        let ps = PostService(client: client)
        self.postService = ps
        _viewModel = State(initialValue: TimelineViewModel(client: client))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    // 横スクロールタブバー（フィードが2件以上の場合のみ表示）
                    feedTabBar

                    Group {
                        if viewModel.isLoading && viewModel.posts.isEmpty {
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if let error = viewModel.errorMessage, viewModel.posts.isEmpty {
                            errorView(message: error)
                        } else {
                            postList
                        }
                    }
                }

                // FAB（投稿作成ボタン）
                Button {
                    showCompose = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                }
                .padding(.trailing, 20)
                .padding(.bottom, evacuationVM?.bannerVisible == true ? 90 : 20)
                .animation(.easeInOut(duration: 0.3), value: evacuationVM?.bannerVisible)
            }
            .navigationTitle(
                viewModel.visibleFeedSources.count > 1
                    ? String(localized: "tab.home")
                    : viewModel.currentFeed.displayName
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // showAllFeedsInSelector=true のときのみフィード選択ボタンを表示
                    // （false のときはタブバーで切替、全フィード非表示時はボタンも非表示）
                    if settings.showAllFeedsInSelector {
                        Button {
                            showFeedSelector = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "list.bullet")
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                            }
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if let handle = authVM.client.currentSession?.handle {
                        Button {
                            showAccountSwitcher = true
                        } label: {
                            Text(abbreviatedHandle(handle))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showFeedSelector) {
                FeedSelectorView(viewModel: viewModel, isPresented: $showFeedSelector)
            }
            .sheet(isPresented: $showAccountSwitcher) {
                AccountPickerView(showCloseButton: true)
                    .environment(authVM)
            }
            // スレッド遷移
            .navigationDestination(item: $selectedPost) { feedPost in
                ThreadView(uri: feedPost.post.uri, postService: postService)
                    .environment(authVM)
            }
            // プロフィール遷移
            .navigationDestination(item: $selectedAuthorDID) { item in
                ProfileScreenView(actor: item.value)
                    .environment(authVM)
            }
            // いいね/リポストユーザー一覧遷移
            .navigationDestination(item: $postActorListType) { listType in
                PostActorListView(listType: listType)
                    .environment(authVM)
            }
            // 引用一覧遷移
            .navigationDestination(item: $quotesPostURI) { item in
                PostQuoteListView(postURI: item.value)
                    .environment(authVM)
            }
            // 投稿作成シート（新規投稿 or 返信 or 引用投稿）
            .sheet(isPresented: $showCompose, onDismiss: { replyToPost = nil; quotePost = nil }) {
                ComposeView(postService: postService, replyTo: replyToPost, quotedPost: quotePost)
                    .environment(AppSettings.shared)
            }
            // macOS: メニューバーからの新規投稿
            .onReceive(NotificationCenter.default.publisher(for: .composeNewPost)) { _ in
                replyToPost = nil; quotePost = nil
                showCompose = true
            }
            // macOS: メニューバーからの再読み込み
            .onReceive(NotificationCenter.default.publisher(for: .reloadTimeline)) { _ in
                Task { await viewModel.refresh() }
            }
        }
        // ミュート確認ダイアログ
        .confirmationDialog(
            muteTargetPost?.author.viewer?.muted == true
                ? String(localized: "profile.unmuteConfirmTitle")
                : String(localized: "profile.muteConfirmTitle"),
            isPresented: Binding(get: { muteTargetPost != nil }, set: { if !$0 { muteTargetPost = nil } }),
            titleVisibility: .visible
        ) {
            if let post = muteTargetPost {
                let isMuted = post.author.viewer?.muted == true
                Button(
                    String(localized: isMuted ? "profile.unmute" : "profile.mute"),
                    role: isMuted ? .none : .destructive
                ) {
                    Task {
                        let graphService = GraphService(client: authVM.client)
                        if isMuted {
                            try? await graphService.unmuteActor(did: post.author.did)
                        } else {
                            try? await graphService.muteActor(did: post.author.did)
                        }
                        muteTargetPost = nil
                    }
                }
                Button(String(localized: "common.cancel"), role: .cancel) { muteTargetPost = nil }
            }
        }
        // ブロック確認ダイアログ
        .confirmationDialog(
            blockTargetPost?.author.viewer?.blocking != nil
                ? String(localized: "profile.unblockConfirmTitle")
                : String(localized: "profile.blockConfirmTitle"),
            isPresented: Binding(get: { blockTargetPost != nil }, set: { if !$0 { blockTargetPost = nil } }),
            titleVisibility: .visible
        ) {
            if let post = blockTargetPost {
                let isBlocked = post.author.viewer?.blocking != nil
                Button(
                    String(localized: isBlocked ? "profile.unblock" : "profile.block"),
                    role: isBlocked ? .none : .destructive
                ) {
                    Task {
                        let graphService = GraphService(client: authVM.client)
                        if isBlocked, let blockUri = post.author.viewer?.blocking {
                            try? await graphService.unblockActor(blockUri: blockUri)
                        } else {
                            _ = try? await graphService.blockActor(did: post.author.did)
                        }
                        blockTargetPost = nil
                    }
                }
                Button(String(localized: "common.cancel"), role: .cancel) { blockTargetPost = nil }
            }
        }
        .task {
            // 避難誘導 ViewModel を接続（BSAF タグ転送用）
            viewModel.evacuationVM = evacuationVM
            await viewModel.loadInitial()
            await viewModel.loadSavedFeeds()
            let interval = settings.timelinePollingInterval
            if interval == .never {
                viewModel.stopPolling()
            } else {
                viewModel.startPolling(intervalSeconds: interval.rawValue)
            }
        }
        .onChange(of: settings.timelinePollingInterval) { _, newInterval in
            if newInterval == .never {
                viewModel.stopPolling()
            } else {
                viewModel.startPolling(intervalSeconds: newInterval.rawValue)
            }
        }
        // ホームタブ再タップ通知を受信 → refresh + スクロール先頭
        .onReceive(NotificationCenter.default.publisher(for: .timelineScrollToTop)) { _ in
            Task {
                await viewModel.refresh()
                if let firstPost = viewModel.posts.first {
                    withAnimation { listScrollProxy?.scrollTo(firstPost.id, anchor: .top) }
                }
            }
        }
    }

    // MARK: - Subviews

    /// 横スクロールタブバー（フィードが2件以上の場合のみ表示）
    @ViewBuilder
    private var feedTabBar: some View {
        let sources = viewModel.visibleFeedSources
        if sources.count > 1 {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                            let isActive = viewModel.currentFeed == source
                            Button {
                                if isActive {
                                    Task {
                                        await viewModel.refresh()
                                        if let firstPost = viewModel.posts.first {
                                            withAnimation { listScrollProxy?.scrollTo(firstPost.id, anchor: .top) }
                                        }
                                    }
                                } else {
                                    Task { await viewModel.selectFeed(source) }
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    Text(source.displayName)
                                        .font(.subheadline)
                                        .fontWeight(isActive ? .semibold : .regular)
                                        .foregroundStyle(isActive ? Color.primary : Color.secondary)
                                        .lineLimit(1)
                                        .padding(.horizontal, 16)
                                        .padding(.top, 8)

                                    // アクティブ時のアンダーライン
                                    Rectangle()
                                        .fill(isActive ? Color.accentColor : Color.clear)
                                        .frame(height: 2)
                                }
                            }
                            .id(index)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .overlay(alignment: .bottom) { Divider() }
                .onChange(of: viewModel.currentFeed) { _, _ in
                    if let activeIndex = sources.firstIndex(of: viewModel.currentFeed) {
                        withAnimation { proxy.scrollTo(activeIndex, anchor: .center) }
                    }
                }
            }
        }
    }

    private var postList: some View {
        ScrollViewReader { proxy in
        List {
            ForEach(viewModel.posts) { feedPost in
                // 既読位置マーカー（この投稿の直前に表示）
                if feedPost.post.uri == viewModel.readMarkerPostURI {
                    readMarkerDivider
                }

                PostCardView(
                    feedPost: feedPost,
                    postService: postService,
                    bsafDuplicateInfo: viewModel.bsafDuplicateInfo[feedPost.post.uri],
                    onTapPost: { post in selectedPost = post },
                    onTapAuthor: { did in selectedAuthorDID = IdentifiableString(did) },
                    onTapReply: { post in replyToPost = post; showCompose = true },
                    onTapLikeCount: { post in postActorListType = .likes(postURI: post.uri) },
                    onTapRepostCount: { post in postActorListType = .reposts(postURI: post.uri) },
                    onTapQuote: { post in quotePost = post; showCompose = true },
                    onTapViewQuotes: { post in quotesPostURI = IdentifiableString(post.uri) },
                    onDelete: { post in viewModel.removePost(uri: post.uri) },
                    onTapMuteUser: { post in muteTargetPost = post },
                    onTapBlockUser: { post in blockTargetPost = post },
                    currentUserDID: authVM.client.currentSession?.did
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .onAppear {
                    if feedPost.id == viewModel.posts.last?.id {
                        Task { await viewModel.loadMore() }
                    }
                }
            }

            if viewModel.isLoading && !viewModel.posts.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .padding()
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.refresh()
        }
        .onAppear { listScrollProxy = proxy }
        } // ScrollViewReader
    }

    /// ナビバーに収まるよう @handle を最大22文字に切り詰める（超過時は末尾に…）
    private func abbreviatedHandle(_ handle: String) -> String {
        let full = "@\(handle)"
        guard full.count > 22 else { return full }
        return String(full.prefix(21)) + "…"
    }

    /// 既読位置マーカー（Desktop版準拠: 青い帯に「↓ ここまで読んだ ↓」）
    private var readMarkerDivider: some View {
        HStack {
            Spacer()
            Text(String(localized: "timeline.readUpToHere"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.blue)
            Spacer()
        }
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.1))
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(String(localized: "feed.retry")) {
                Task { await viewModel.loadInitial() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
