// ThreadView.swift
// kazahana-ios
// 投稿スレッド表示画面

import SwiftUI

struct ThreadView: View {

    @Environment(AuthViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ThreadViewModel
    @State private var replyToPost: PostView? = nil
    @State private var selectedPost: FeedViewPost? = nil
    @State private var postActorListType: PostActorListType? = nil
    @State private var quotesPostURI: IdentifiableString? = nil
    @State private var quotePost: PostView? = nil
    @State private var selectedAuthorDID: IdentifiableString? = nil

    // フォーカス投稿のいいね/リポスト/ブックマーク状態（楽観的UI）
    @State private var isLiked = false
    @State private var likeCount = 0
    @State private var isReposted = false
    @State private var repostCount = 0
    @State private var isBookmarked = false
    @State private var isThreadMuted = false
    @State private var likeUri: String? = nil
    @State private var repostUri: String? = nil
    @State private var showFocusedDeleteConfirm = false
    @State private var reportTarget: ReportTarget? = nil

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
        .navigationTitle(String(localized: "thread.title"))
        .toolbar(.hidden, for: .navigationBar)
        .enableInteractivePop()
        .overlay(alignment: .topLeading) {
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
        .navigationDestination(item: $quotesPostURI) { item in
            PostQuoteListView(postURI: item.value)
                .environment(authVM)
        }
        // プロフィール遷移
        .navigationDestination(item: $selectedAuthorDID) { item in
            ProfileScreenView(actor: item.value)
                .environment(authVM)
        }
        .sheet(item: $reportTarget) { target in
            ReportView(target: target, postService: postService)
        }
        .task {
            await viewModel.load()
            if let post = viewModel.thread?.post {
                isLiked = post.viewer?.like != nil
                likeCount = post.likeCount ?? 0
                isReposted = post.viewer?.repost != nil
                repostCount = post.repostCount ?? 0
                isBookmarked   = post.viewer?.bookmarked == true
                isThreadMuted  = post.viewer?.threadMuted == true
                likeUri        = post.viewer?.like
                repostUri      = post.viewer?.repost
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
                                onTapAuthor: { did in selectedAuthorDID = IdentifiableString(did) },
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
                    onTapAuthor: { did in selectedAuthorDID = IdentifiableString(did) },
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
        let moderation = ModerationService().moderatePost(post)

        return VStack(alignment: .leading, spacing: 10) {
            // 著者（タップでプロフィール遷移）
            HStack(spacing: 10) {
                Button {
                    selectedAuthorDID = IdentifiableString(post.author.did)
                } label: {
                    AvatarView(url: post.author.avatar, size: 48)
                }
                .buttonStyle(.plain)
                Button {
                    selectedAuthorDID = IdentifiableString(post.author.did)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(post.author.displayNameOrHandle)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            if isBotAccount(did: post.author.did, labels: post.author.labels) {
                                BotBadge(size: 14)
                            }
                        }
                        Text("@\(post.author.handle)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                focusedPostMoreMenu(post: post)
            }

            // 本文
            if !post.record.text.isEmpty {
                Text(RichTextParser.attributedString(text: post.record.text, facets: post.record.facets))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 埋め込み（メディアブラー対応）
            if let embed = post.embed {
                if moderation.decision == .mediaBlur {
                    ZStack {
                        embedView(embed)
                        MediaBlurOverlay(message: moderation.message)
                    }
                } else {
                    embedView(embed)
                }
            }

            // langs / via / モデレーションラベル
            let activeLabels = focusedActiveLabels(post: post)
            if post.record.via != nil || !(post.record.langs ?? []).isEmpty || !activeLabels.isEmpty {
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
                    ForEach(activeLabels, id: \.self) { label in
                        Text(focusedLabelBadgeName(label))
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
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
                    countItem(count: repostCount, label: String(localized: "post.reposted"))
                }
                .buttonStyle(.plain)
                .disabled(repostCount == 0)

                Button {
                    quotesPostURI = IdentifiableString(post.uri)
                } label: {
                    countItem(count: post.quoteCount ?? 0, label: String(localized: "postList.quotedBy"))
                }
                .buttonStyle(.plain)
                .disabled((post.quoteCount ?? 0) == 0)

                Button {
                    postActorListType = .likes(postURI: post.uri)
                } label: {
                    countItem(count: likeCount, label: String(localized: "profile.likes"))
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

                // ブックマーク
                actionButton(icon: isBookmarked ? "bookmark.fill" : "bookmark", color: isBookmarked ? .orange : .secondary) {
                    Task { await toggleBookmark(post: post) }
                }

                Spacer()

                // 共有
                actionButton(icon: "square.and.arrow.up", color: .secondary) {
                    let url = "https://bsky.app/profile/\(post.author.handle)/post/\(post.uri.components(separatedBy: "/").last ?? "")"
                    sharePost(urlString: url)
                }
            }
            .padding(.vertical, 4)
        }
        .padding(16)
        .alert(String(localized: "post.deleteConfirm"), isPresented: $showFocusedDeleteConfirm) {
            Button(String(localized: "post.deleteAction"), role: .destructive) {
                Task {
                    if let post = viewModel.thread?.post {
                        try? await postService.deletePost(uri: post.uri)
                        viewModel.thread = nil
                    }
                }
            }
            Button(String(localized: "post.deleteCancel"), role: .cancel) {
                showFocusedDeleteConfirm = false
            }
        } message: {
            Text(String(localized: "post.deleteConfirm"))
        }
    }

    @ViewBuilder
    private func focusedPostMoreMenu(post: PostView) -> some View {
        let currentDID = authVM.client.currentSession?.did
        Menu {
            // 共有シート
            Button {
                let url = "https://bsky.app/profile/\(post.author.handle)/post/\(post.uri.components(separatedBy: "/").last ?? "")"
                sharePost(urlString: url)
            } label: {
                Label(String(localized: "post.share"), systemImage: "square.and.arrow.up")
            }

            // リンクをコピー
            Button {
                let url = "https://bsky.app/profile/\(post.author.handle)/post/\(post.uri.components(separatedBy: "/").last ?? "")"
                UIPasteboard.general.string = url
            } label: {
                Label(String(localized: "post.copyLink"), systemImage: "link")
            }

            // 翻訳
            Button {
                let text = post.record.text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let langCode = Locale.current.language.languageCode?.identifier ?? "en"
                if let url = URL(string: "https://translate.google.com/?text=\(text)&sl=auto&tl=\(langCode)") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label(String(localized: "post.translate"), systemImage: "character.bubble")
            }

            // 他人の投稿のみ：非表示・通報
            if let currentDID, currentDID != post.author.did {
                Divider()
                Button {
                    Task { try? await postService.hidePost(uri: post.uri) }
                } label: {
                    Label(String(localized: "post.hidePost"), systemImage: "eye.slash")
                }
                Button {
                    reportTarget = .post(uri: post.uri, cid: post.cid)
                } label: {
                    Label(String(localized: "post.reportPost"), systemImage: "flag")
                }
                Button {
                    reportTarget = .account(did: post.author.did)
                } label: {
                    Label(String(localized: "post.reportAccount"), systemImage: "person.badge.minus")
                }
            }

            // 全投稿：スレッドミュート
            Divider()
            Button {
                Task { await toggleMuteThread(post: post) }
            } label: {
                Label(
                    String(localized: isThreadMuted ? "post.unmuteThread" : "post.muteThread"),
                    systemImage: isThreadMuted ? "bell" : "bell.slash"
                )
            }

            // 自分の投稿のみ削除
            if let currentDID, currentDID == post.author.did {
                Divider()
                Button(role: .destructive) {
                    showFocusedDeleteConfirm = true
                } label: {
                    Label(String(localized: "post.delete"), systemImage: "trash")
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

    private func toggleBookmark(post: PostView) async {
        if isBookmarked {
            isBookmarked = false
            try? await postService.unbookmark(uri: post.uri)
        } else {
            isBookmarked = true
            do {
                try await postService.bookmark(uri: post.uri, cid: post.cid)
            } catch {
                isBookmarked = false
            }
        }
    }

    private func toggleMuteThread(post: PostView) async {
        if isThreadMuted {
            isThreadMuted = false
            try? await postService.unmuteThread(root: post.uri)
        } else {
            isThreadMuted = true
            do {
                try await postService.muteThread(root: post.uri)
            } catch {
                isThreadMuted = false
            }
        }
    }

    // MARK: - Helpers

    private func focusedActiveLabels(post: PostView) -> [String] {
        let systemLabels: Set<String> = ["!hide", "!warn", "!no-unauthenticated"]
        return (post.labels ?? [])
            .filter { $0.neg != true && !systemLabels.contains($0.val) }
            .map { $0.val }
    }

    private func focusedLabelBadgeName(_ val: String) -> String {
        switch val {
        case "porn":          return String(localized: "moderation.porn")
        case "sexual":        return String(localized: "moderation.sexual")
        case "nudity":        return String(localized: "moderation.nudity")
        case "graphic-media": return String(localized: "moderation.graphicMedia")
        case "gore":          return String(localized: "moderation.gore")
        default:              return val
        }
    }

    private func sharePost(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            var presenter = root
            while let presented = presenter.presentedViewController {
                presenter = presented
            }
            av.popoverPresentationController?.sourceView = presenter.view
            presenter.present(av, animated: true)
        }
    }

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
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.secondary)
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button(String(localized: "feed.retry")) { Task { await viewModel.load() } }.buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
