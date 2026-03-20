// TimelineView.swift
// kazahana-ios
// ホームタイムライン画面（FAB・スレッド遷移・インタラクション対応）

import SwiftUI

struct TimelineView: View {

    @Environment(AuthViewModel.self) private var authVM
    @Environment(AppSettings.self) private var settings
    @State private var viewModel: TimelineViewModel
    @State private var showCompose: Bool = false
    @State private var replyToPost: PostView? = nil
    @State private var quotePost: PostView? = nil
    @State private var showFeedSelector: Bool = false
    @State private var selectedPost: FeedViewPost? = nil
    @State private var selectedAuthorDID: IdentifiableString? = nil
    @State private var postActorListType: PostActorListType? = nil

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
                .padding(.bottom, 20)
            }
            .navigationTitle(
                viewModel.visibleFeedSources.count > 1
                    ? String(localized: "tab.home")
                    : viewModel.currentFeed.displayName
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // タブバー非表示時 or showAllFeedsInSelector=true のときにフィード選択ボタンを表示
                    if viewModel.visibleFeedSources.count <= 1 || settings.showAllFeedsInSelector {
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

            }
            .sheet(isPresented: $showFeedSelector) {
                FeedSelectorView(viewModel: viewModel, isPresented: $showFeedSelector)
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
            // 投稿作成シート（新規投稿 or 返信 or 引用投稿）
            .sheet(isPresented: $showCompose, onDismiss: { replyToPost = nil; quotePost = nil }) {
                ComposeView(postService: postService, replyTo: replyToPost, quotedPost: quotePost)
                    .environment(AppSettings.shared)
            }
        }
        .task {
            await viewModel.loadInitial()
            await viewModel.loadSavedFeeds()
            viewModel.startPolling(intervalSeconds: settings.timelinePollingInterval.rawValue)
        }
        .onChange(of: settings.timelinePollingInterval) { _, newInterval in
            viewModel.startPolling(intervalSeconds: newInterval.rawValue)
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
                                    Task { await viewModel.refresh() }
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
        List {
            ForEach(viewModel.posts) { feedPost in
                PostCardView(
                    feedPost: feedPost,
                    postService: postService,
                    onTapPost: { post in selectedPost = post },
                    onTapAuthor: { did in selectedAuthorDID = IdentifiableString(did) },
                    onTapReply: { post in replyToPost = post; showCompose = true },
                    onTapLikeCount: { post in postActorListType = .likes(postURI: post.uri) },
                    onTapRepostCount: { post in postActorListType = .reposts(postURI: post.uri) },
                    onTapQuote: { post in quotePost = post; showCompose = true },
                    onDelete: { post in viewModel.removePost(uri: post.uri) },
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
