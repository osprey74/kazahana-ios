// ThreadView.swift
// kazahana-ios
// 投稿スレッド表示画面

import SwiftUI

struct ThreadView: View {

    @Environment(AuthViewModel.self) private var authVM
    @State private var viewModel: ThreadViewModel
    @State private var replyToPost: PostView? = nil
    @State private var selectedPost: FeedViewPost? = nil
    @State private var postActorListType: PostActorListType? = nil
    @State private var quotePost: PostView? = nil

    // フォーカス投稿のいいね/リポスト状態（楽観的UI）
    @State private var isLiked = false
    @State private var likeCount = 0
    @State private var isReposted = false
    @State private var repostCount = 0
    @State private var likeUri: String? = nil
    @State private var repostUri: String? = nil
    @State private var showFocusedDeleteConfirm = false

    let postService: PostService

    init(uri: String, postService: PostService) {
        self.postService = postService
        _viewModel = State(initialValue: ThreadViewModel(postService: postService, uri: uri))
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.thread == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage, viewModel.thread == nil {
                errorView(message: error)
            } else if let thread = viewModel.thread {
                threadContent(thread)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("スレッド")
        .navigationDestination(item: $selectedPost) { feedPost in
            ThreadView(uri: feedPost.post.uri, postService: postService)
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
        .navigationDestination(item: $postActorListType) { listType in
            PostActorListView(listType: listType)
                .environment(authVM)
        }
        .task {
            await viewModel.load()
            if let post = viewModel.thread?.post {
                isLiked = post.viewer?.like != nil
                likeCount = post.likeCount ?? 0
                isReposted = post.viewer?.repost != nil
                repostCount = post.repostCount ?? 0
                likeUri = post.viewer?.like
                repostUri = post.viewer?.repost
            }
        }
    }

    // MARK: - Thread content

    private func threadContent(_ thread: ThreadViewPost) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // 親投稿（スレッドを遡る）
                if let parent = thread.parent {
                    parentChain(parent)
                }

                // フォーカス投稿（強調表示）
                if let post = thread.post {
                    focusedPostView(post: post)
                    Divider()
                }

                // 返信一覧
                if let replies = thread.replies {
                    ForEach(Array(replies.enumerated()), id: \.offset) { _, reply in
                        if let replyPost = reply.post {
                            let feedPost = FeedViewPost(post: replyPost, reply: nil, reason: nil)
                            PostCardView(
                                feedPost: feedPost,
                                postService: postService,
                                onTapPost: { post in selectedPost = post },
                                onTapReply: { post in replyToPost = post },
                                onDelete: { post in viewModel.removeReply(uri: post.uri) },
                                currentUserDID: authVM.client.currentSession?.did
                            )
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 親投稿チェーン（再帰）

    private func parentChain(_ thread: ThreadViewPost) -> AnyView {
        AnyView(Group {
            if let parent = thread.parent {
                parentChain(parent)
            }
            if let post = thread.post {
                PostCardView(
                    feedPost: FeedViewPost(post: post, reply: nil, reason: nil),
                    postService: postService,
                    onTapPost: { p in selectedPost = p },
                    onTapReply: { post in replyToPost = post },
                    currentUserDID: authVM.client.currentSession?.did
                )
                HStack {
                    Spacer().frame(width: 28 + 16)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 2, height: 16)
                    Spacer()
                }
            }
        })
    }

    // MARK: - フォーカス投稿

    private func focusedPostView(post: PostView) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // 著者
            HStack(spacing: 10) {
                AvatarView(url: post.author.avatar, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.author.displayNameOrHandle)
                        .font(.headline)
                    Text("@\(post.author.handle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                focusedPostMoreMenu(post: post)
            }

            // 本文
            if !post.record.text.isEmpty {
                Text(RichTextParser.attributedString(text: post.record.text, facets: post.record.facets))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 埋め込み
            if let embed = post.embed {
                embedView(embed)
            }

            // langs / via
            if post.record.via != nil || !(post.record.langs ?? []).isEmpty {
                HStack(spacing: 4) {
                    if let langs = post.record.langs, !langs.isEmpty {
                        Text(langs.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                    }
                    if let via = post.record.via {
                        Text("via \(via)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // 投稿日時
            Text(formattedDate(post.indexedAt))
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            // カウント行（タップでユーザーリスト）
            HStack(spacing: 20) {
                Button {
                    postActorListType = .reposts(postURI: post.uri)
                } label: {
                    countItem(count: repostCount, label: "リポスト")
                }
                .buttonStyle(.plain)
                .disabled(repostCount == 0)

                countItem(count: post.quoteCount ?? 0, label: "引用")

                Button {
                    postActorListType = .likes(postURI: post.uri)
                } label: {
                    countItem(count: likeCount, label: "いいね")
                }
                .buttonStyle(.plain)
                .disabled(likeCount == 0)
            }

            Divider()

            // アクションバー
            HStack(spacing: 0) {
                // 返信
                actionButton(icon: "bubble.left", color: .secondary) {
                    replyToPost = post
                }

                Spacer()

                // リポスト
                actionButton(
                    icon: "arrow.2.squarepath",
                    color: isReposted ? .green : .secondary,
                    label: repostCount > 0 ? "\(repostCount)" : nil
                ) {
                    Task { await toggleRepost(post: post) }
                }

                Spacer()

                // いいね
                actionButton(
                    icon: isLiked ? "heart.fill" : "heart",
                    color: isLiked ? .red : .secondary,
                    label: likeCount > 0 ? "\(likeCount)" : nil
                ) {
                    Task { await toggleLike(post: post) }
                }

                Spacer()

                // 引用投稿
                actionButton(icon: "quote.bubble", color: .secondary) {
                    quotePost = post
                }

                Spacer()

                // 共有（将来用）
                actionButton(icon: "square.and.arrow.up", color: .secondary) { }
            }
            .padding(.vertical, 4)
        }
        .padding(16)
        .confirmationDialog("投稿を削除します", isPresented: $showFocusedDeleteConfirm, titleVisibility: .visible) {
            Button("削除する", role: .destructive) {
                Task {
                    if let post = viewModel.thread?.post {
                        try? await postService.deletePost(uri: post.uri)
                        viewModel.thread = nil
                    }
                }
            }
            Button("キャンセル", role: .cancel) {
                showFocusedDeleteConfirm = false
            }
        } message: {
            Text("この操作は取り消せません")
        }
    }

    @ViewBuilder
    private func focusedPostMoreMenu(post: PostView) -> some View {
        let currentDID = authVM.client.currentSession?.did
        Menu {
            // リンクをコピー
            Button {
                let url = "https://bsky.app/profile/\(post.author.handle)/post/\(post.uri.components(separatedBy: "/").last ?? "")"
                UIPasteboard.general.string = url
            } label: {
                Label("リンクをコピー", systemImage: "link")
            }

            // 翻訳
            Button {
                let text = post.record.text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let url = URL(string: "https://translate.google.com/?text=\(text)&sl=auto&tl=ja") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("翻訳", systemImage: "character.bubble")
            }

            // 自分の投稿のみ削除
            if let currentDID, currentDID == post.author.did {
                Divider()
                Button(role: .destructive) {
                    showFocusedDeleteConfirm = true
                } label: {
                    Label("削除", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .padding(.leading, 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func actionButton(icon: String, color: Color, label: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                if let label {
                    Text(label)
                        .font(.subheadline)
                }
            }
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }

    // MARK: - いいね / リポスト

    private func toggleLike(post: PostView) async {
        let prev = (isLiked, likeCount, likeUri)
        if isLiked, let uri = likeUri {
            isLiked = false; likeCount -= 1; likeUri = nil
            do { try await postService.unlike(likeUri: uri) }
            catch { isLiked = prev.0; likeCount = prev.1; likeUri = prev.2 }
        } else {
            isLiked = true; likeCount += 1
            do {
                let response = try await postService.like(uri: post.uri, cid: post.cid)
                likeUri = response.uri
            } catch { isLiked = prev.0; likeCount = prev.1; likeUri = prev.2 }
        }
    }

    private func toggleRepost(post: PostView) async {
        let prev = (isReposted, repostCount, repostUri)
        if isReposted, let uri = repostUri {
            isReposted = false; repostCount -= 1; repostUri = nil
            do { try await postService.unrepost(repostUri: uri) }
            catch { isReposted = prev.0; repostCount = prev.1; repostUri = prev.2 }
        } else {
            isReposted = true; repostCount += 1
            do {
                let response = try await postService.repost(uri: post.uri, cid: post.cid)
                repostUri = response.uri
            } catch { isReposted = prev.0; repostCount = prev.1; repostUri = prev.2 }
        }
    }

    // MARK: - Helpers

    private func countItem(count: Int, label: String) -> some View {
        HStack(spacing: 4) {
            Text("\(count)").font(.subheadline.weight(.bold))
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func embedView(_ embed: PostEmbed) -> some View {
        switch embed {
        case .images(let images): ImageGridView(images: images.images)
        case .external(let ext): LinkCardView(external: ext.external)
        case .record(let rec):
            if let r = rec.record { QuoteEmbedView(record: r) }
        default: EmptyView()
        }
    }

    private func formattedDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateString) ?? ISO8601DateFormatter().date(from: dateString) else {
            return dateString
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: "ja_JP")
        df.dateFormat = "yyyy年M月d日 H:mm"
        return df.string(from: date)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.secondary)
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("再試行") { Task { await viewModel.load() } }.buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
