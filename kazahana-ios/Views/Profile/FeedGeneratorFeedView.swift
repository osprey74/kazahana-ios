// FeedGeneratorFeedView.swift
// kazahana-ios
// カスタムフィードの投稿一覧画面（app.bsky.feed.getFeed）

import SwiftUI

/// カスタムフィード（GeneratorView）の投稿を表示する画面
struct FeedGeneratorFeedView: View {
    @Environment(AuthViewModel.self) private var authVM
    let feed: GeneratorView

    @State private var posts: [FeedViewPost] = []
    @State private var cursor: String? = nil
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var errorMessage: String? = nil

    @State private var selectedPost: FeedViewPost? = nil
    @State private var replyToPost: PostView? = nil
    @State private var quotePost: PostView? = nil
    @State private var selectedAuthorDID: IdentifiableString? = nil
    @State private var postActorListType: PostActorListType? = nil

    private var feedService: FeedService {
        FeedService(client: authVM.client)
    }
    private var postService: PostService {
        PostService(client: authVM.client)
    }

    var body: some View {
        Group {
            if isLoading && posts.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, posts.isEmpty {
                errorView(message: error)
            } else if posts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "feed.empty"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                postList
            }
        }
        .navigationTitle(feed.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadInitial() }
        .navigationDestination(item: $selectedPost) { feedPost in
            ThreadView(uri: feedPost.post.uri, postService: postService)
                .environment(authVM)
        }
        .navigationDestination(item: $selectedAuthorDID) { item in
            ProfileScreenView(actor: item.value)
                .environment(authVM)
        }
        .navigationDestination(item: $postActorListType) { listType in
            PostActorListView(listType: listType)
                .environment(authVM)
        }
        .sheet(item: $replyToPost) { replyTo in
            ComposeView(postService: postService, replyTo: replyTo)
                .environment(AppSettings.shared)
        }
        .sheet(item: $quotePost) { quoted in
            ComposeView(postService: postService, quotedPost: quoted)
                .environment(AppSettings.shared)
        }
    }

    private var postList: some View {
        List {
            ForEach(posts) { feedPost in
                PostCardView(
                    feedPost: feedPost,
                    postService: postService,
                    onTapPost: { post in selectedPost = post },
                    onTapAuthor: { did in selectedAuthorDID = IdentifiableString(did) },
                    onTapReply: { post in replyToPost = post },
                    onTapLikeCount: { post in postActorListType = .likes(postURI: post.uri) },
                    onTapRepostCount: { post in postActorListType = .reposts(postURI: post.uri) },
                    onTapQuote: { post in quotePost = post },
                    currentUserDID: authVM.client.currentSession?.did
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .onAppear {
                    if feedPost.id == posts.last?.id {
                        Task { await loadMore() }
                    }
                }
            }
            if isLoading && !posts.isEmpty {
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
        .refreshable { await loadInitial() }
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
                Task { await loadInitial() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        cursor = nil
        hasMore = true
        do {
            let response = try await feedService.getFeed(feedURI: feed.uri, limit: 50)
            posts = response.feed
            cursor = response.cursor
            hasMore = response.cursor != nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func loadMore() async {
        guard !isLoading, hasMore, let currentCursor = cursor else { return }
        isLoading = true
        do {
            let response = try await feedService.getFeed(feedURI: feed.uri, limit: 50, cursor: currentCursor)
            posts.append(contentsOf: response.feed)
            cursor = response.cursor
            hasMore = response.cursor != nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
