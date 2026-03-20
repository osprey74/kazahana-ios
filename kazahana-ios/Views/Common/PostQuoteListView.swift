// PostQuoteListView.swift
// kazahana-ios
// 引用投稿一覧画面

import SwiftUI

struct PostQuoteListView: View {
    @Environment(AuthViewModel.self) private var authVM
    let postURI: String

    @State private var posts: [PostView] = []
    @State private var cursor: String? = nil
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var selectedPost: FeedViewPost? = nil
    @State private var selectedAuthorDID: IdentifiableString? = nil
    @State private var replyToPost: PostView? = nil
    @State private var quotePost: PostView? = nil
    @State private var postActorListType: PostActorListType? = nil

    var body: some View {
        Group {
            if isLoading && posts.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, posts.isEmpty {
                VStack(spacing: 12) {
                    Text(error).foregroundStyle(.secondary)
                    Button(String(localized: "postList.retry")) {
                        Task { await loadInitial() }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if posts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "quote.bubble")
                        .font(.largeTitle).foregroundStyle(.secondary)
                    Text(String(localized: "postList.noQuotes")).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let postService = PostService(client: authVM.client)
                List {
                    ForEach(posts) { post in
                        let feedPost = FeedViewPost(post: post, reply: nil, reason: nil)
                        PostCardView(
                            feedPost: feedPost,
                            postService: postService,
                            onTapPost: { fp in selectedPost = fp },
                            onTapAuthor: { did in selectedAuthorDID = IdentifiableString(did) },
                            onTapReply: { p in replyToPost = p },
                            onTapLikeCount: { p in postActorListType = .likes(postURI: p.uri) },
                            onTapRepostCount: { p in postActorListType = .reposts(postURI: p.uri) },
                            onTapQuote: { p in quotePost = p },
                            onDelete: { p in posts.removeAll { $0.uri == p.uri } },
                            currentUserDID: authVM.client.currentSession?.did
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .onAppear {
                            if post.id == posts.last?.id {
                                Task { await loadMore() }
                            }
                        }
                    }
                    if isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(String(localized: "postList.quotedBy"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedPost) { feedPost in
            ThreadView(uri: feedPost.post.uri, postService: PostService(client: authVM.client))
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
            ComposeView(postService: PostService(client: authVM.client), replyTo: replyTo)
                .environment(AppSettings.shared)
        }
        .sheet(item: $quotePost) { quoted in
            ComposeView(postService: PostService(client: authVM.client), quotedPost: quoted)
                .environment(AppSettings.shared)
        }
        .task { await loadInitial() }
    }

    // MARK: - Data Loading

    private func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        cursor = nil
        hasMore = true
        let postService = PostService(client: authVM.client)
        do {
            let res = try await postService.getQuotes(uri: postURI, cursor: nil)
            posts = res.posts
            cursor = res.cursor
            hasMore = res.cursor != nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        let postService = PostService(client: authVM.client)
        do {
            let res = try await postService.getQuotes(uri: postURI, cursor: cursor)
            posts.append(contentsOf: res.posts)
            cursor = res.cursor
            hasMore = res.cursor != nil
        } catch {}
        isLoading = false
    }
}
