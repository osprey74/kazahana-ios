// PostCardView.swift
// kazahana-ios
// タイムラインの投稿カード（インタラクション対応・リッチテキスト対応）

import SwiftUI

struct PostCardView: View {

    let feedPost: FeedViewPost
    let postService: PostService?
    /// スレッド遷移先を親に通知するコールバック
    var onTapPost: ((FeedViewPost) -> Void)?
    /// アバター/著者名タップでプロフィール遷移するコールバック
    var onTapAuthor: ((String) -> Void)?
    /// 返信ボタンタップ（ComposeView を開く）
    var onTapReply: ((PostView) -> Void)?
    /// いいね数タップ（いいねしたユーザー一覧）
    var onTapLikeCount: ((PostView) -> Void)?
    /// リポスト数タップ（リポストしたユーザー一覧）
    var onTapRepostCount: ((PostView) -> Void)?
    /// 引用して投稿ボタンタップ
    var onTapQuote: ((PostView) -> Void)?
    /// 引用一覧を見るボタンタップ
    var onTapViewQuotes: ((PostView) -> Void)?
    /// 投稿削除後の通知
    var onDelete: ((PostView) -> Void)?
    /// ブックマーク解除後の通知
    var onUnbookmark: ((PostView) -> Void)?
    /// 投稿著者をミュート/アンミュート（他人の投稿のみ）
    var onTapMuteUser: ((PostView) -> Void)?
    /// 投稿著者をブロック/アンブロック（他人の投稿のみ）
    var onTapBlockUser: ((PostView) -> Void)?
    /// 現在ログイン中のユーザー DID（自分の投稿かどうかの判定に使用）
    var currentUserDID: String?
    /// BSAF 重複情報（この投稿が primary の場合にセット）
    var bsafDuplicateInfo: BsafDuplicateInfo?

    // ローカル状態（楽観的 UI 更新用）
    @State private var isLiked: Bool
    @State private var likeCount: Int
    @State private var isReposted: Bool
    @State private var repostCount: Int
    @State private var isBookmarked: Bool
    @State private var isThreadMuted: Bool
    @State private var likeUri: String?
    @State private var repostUri: String?
    @State private var showDeleteConfirm = false
    @State private var reportTarget: ReportTarget? = nil
    @State private var isSavingMedia = false
    #if targetEnvironment(macCatalyst)
    @State private var isHovered = false
    #endif
    @State private var saveToastMessage: String? = nil

    private var post: PostView { feedPost.post }
    private var author: ProfileViewBasic { post.author }

    private var moderationResult: ModerationResult {
        ModerationService().moderatePost(post)
    }

    /// BSAF タグのパース結果（BSAF 有効 かつ 登録済み Bot の投稿のみ）
    private var bsafParsedTags: BsafParsedTags? {
        guard AppSettings.shared.bsafEnabled,
              AppSettings.shared.findRegisteredBot(did: author.did) != nil,
              let tags = post.record.tags else { return nil }
        return BsafService.parseBsafTags(tags)
    }

    /// 深刻度カラー（BSAF 対応投稿のみ）
    private var bsafBorderColor: Color? {
        guard let parsed = bsafParsedTags else { return nil }
        return BsafService.severityBorderColor(for: parsed.value)
    }

    init(
        feedPost: FeedViewPost,
        postService: PostService? = nil,
        bsafDuplicateInfo: BsafDuplicateInfo? = nil,
        onTapPost: ((FeedViewPost) -> Void)? = nil,
        onTapAuthor: ((String) -> Void)? = nil,
        onTapReply: ((PostView) -> Void)? = nil,
        onTapLikeCount: ((PostView) -> Void)? = nil,
        onTapRepostCount: ((PostView) -> Void)? = nil,
        onTapQuote: ((PostView) -> Void)? = nil,
        onTapViewQuotes: ((PostView) -> Void)? = nil,
        onDelete: ((PostView) -> Void)? = nil,
        onUnbookmark: ((PostView) -> Void)? = nil,
        onTapMuteUser: ((PostView) -> Void)? = nil,
        onTapBlockUser: ((PostView) -> Void)? = nil,
        currentUserDID: String? = nil
    ) {
        self.feedPost = feedPost
        self.postService = postService
        self.bsafDuplicateInfo = bsafDuplicateInfo
        self.onTapPost = onTapPost
        self.onTapAuthor = onTapAuthor
        self.onTapReply = onTapReply
        self.onTapLikeCount = onTapLikeCount
        self.onTapRepostCount = onTapRepostCount
        self.onTapQuote = onTapQuote
        self.onTapViewQuotes = onTapViewQuotes
        self.onDelete = onDelete
        self.onUnbookmark = onUnbookmark
        self.onTapMuteUser = onTapMuteUser
        self.onTapBlockUser = onTapBlockUser
        self.currentUserDID = currentUserDID
        _isLiked      = State(initialValue: feedPost.post.viewer?.like != nil)
        _likeCount    = State(initialValue: feedPost.post.likeCount ?? 0)
        _isReposted   = State(initialValue: feedPost.post.viewer?.repost != nil)
        _repostCount  = State(initialValue: feedPost.post.repostCount ?? 0)
        _isBookmarked   = State(initialValue: feedPost.post.viewer?.bookmarked == true)
        _isThreadMuted  = State(initialValue: feedPost.post.viewer?.threadMuted == true)
        _likeUri        = State(initialValue: feedPost.post.viewer?.like)
        _repostUri      = State(initialValue: feedPost.post.viewer?.repost)
    }

    var body: some View {
        let moderation = moderationResult

        // filter 判定は ViewModel 側で除外するが安全策として非表示
        if moderation.decision == .filter {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // リポストヘッダー
                if let reason = feedPost.reason, reason.type == "app.bsky.feed.defs#reasonRepost" {
                    repostHeader(by: reason.by)
                }

                ZStack(alignment: .center) {
                    HStack(alignment: .top, spacing: 12) {
                        // アバター（タップでプロフィール遷移）
                        Button {
                            onTapAuthor?(author.did)
                        } label: {
                            AvatarView(url: author.avatar, size: 44)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 6) {
                            authorRow

                            // 返信先表示
                            if let reply = feedPost.reply, let parentUri = reply.parent?.uri {
                                replyIndicator(parentUri: parentUri)
                            }

                            // langs / via / モデレーションラベル
                            if post.record.via != nil || !(post.record.langs ?? []).isEmpty || !activeLabels.isEmpty {
                                langsViaRow
                            }

                            // 本文（リッチテキスト）
                            if !post.record.text.isEmpty {
                                Text(RichTextParser.attributedString(
                                    text: post.record.text,
                                    facets: post.record.facets
                                ))
                                .font(.body)
                                .lineLimit(20)
                                .fixedSize(horizontal: false, vertical: true)
                                .environment(\.openURL, OpenURLAction { url in
                                    if url.scheme == "kazahana" {
                                        // kazahana:// スキームは NotificationCenter 経由で ContentView に転送
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

                            // BSAF タグバッジ
                            if let tags = post.record.tags, bsafParsedTags != nil {
                                bsafTagsRow(tags: tags)
                            }

                            // BSAF 重複投稿インジケーター
                            if let dupInfo = bsafDuplicateInfo, !dupInfo.duplicateHandles.isEmpty {
                                bsafDuplicateRow(count: dupInfo.duplicateHandles.count)
                            }

                            // 埋め込みコンテンツ（メディアブラー対応）
                            if let embed = post.embed {
                                moderatedEmbedView(embed, moderation: moderation)
                            }

                            // アクションバー
                            actionBar
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    // カード全体タップでポスト詳細へ（アバター・アクションバーを除くエリア）
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTapPost?(feedPost)
                    }
                    .contextMenu {
                        // 返信
                        if let onTapReply {
                            Button {
                                onTapReply(post)
                            } label: {
                                Label(String(localized: "compose.reply"), systemImage: "bubble.left")
                            }
                        }
                        // 引用
                        if let onTapQuote {
                            Button {
                                onTapQuote(post)
                            } label: {
                                Label(String(localized: "post.quoteRepost"), systemImage: "quote.bubble")
                            }
                        }
                        Divider()
                        // 共有
                        Button {
                            let url = "https://bsky.app/profile/\(author.handle)/post/\(post.uri.components(separatedBy: "/").last ?? "")"
                            sharePost(urlString: url)
                        } label: {
                            Label(String(localized: "post.share"), systemImage: "square.and.arrow.up")
                        }
                        // リンクコピー
                        Button {
                            let url = "https://bsky.app/profile/\(author.handle)/post/\(post.uri.components(separatedBy: "/").last ?? "")"
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
                    }

                    // 投稿全体ブラー（blur 判定時）
                    if moderation.decision == .blur {
                        PostBlurOverlay(message: moderation.message)
                            .padding(.horizontal, 16)
                    }
                }

                Divider()
            }
            .overlay(alignment: .leading) {
                // BSAF 深刻度カラーボーダー（左側）
                if let color = bsafBorderColor {
                    Rectangle()
                        .fill(color)
                        .frame(width: 8)
                }
            }
            #if targetEnvironment(macCatalyst)
            .background(isHovered ? Color.secondary.opacity(0.06) : Color.clear)
            .onHover { hovering in isHovered = hovering }
            #endif
            .overlay(alignment: .bottom) {
                if let msg = saveToastMessage {
                    Text(msg)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 8)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: saveToastMessage)
            .overlay {
                if isSavingMedia {
                    ZStack {
                        Color.black.opacity(0.45)
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.5)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isSavingMedia)
            .alert(String(localized: "post.deleteConfirm"), isPresented: $showDeleteConfirm) {
                Button(String(localized: "post.deleteAction"), role: .destructive) {
                    Task { await deletePost() }
                }
                Button(String(localized: "post.deleteCancel"), role: .cancel) {
                    showDeleteConfirm = false
                }
            } message: {
                Text(String(localized: "post.deleteConfirm"))
            }
            .sheet(item: $reportTarget) { target in
                if let postService {
                    ReportView(target: target, postService: postService)
                }
            }
        } // else
    }

    // MARK: - Subviews

    @ViewBuilder
    private var langsViaRow: some View {
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
                Text(labelBadgeName(label))
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
            }
        }
    }

    /// 表示するモデレーションラベル値（neg=true・システムラベルを除外）
    private var activeLabels: [String] {
        let systemLabels: Set<String> = ["!hide", "!warn", "!no-unauthenticated"]
        return (post.labels ?? [])
            .filter { $0.neg != true && !systemLabels.contains($0.val) }
            .map { $0.val }
    }

    private func labelBadgeName(_ val: String) -> String {
        switch val {
        case "porn":          return String(localized: "moderation.porn")
        case "sexual":        return String(localized: "moderation.sexual")
        case "nudity":        return String(localized: "moderation.nudity")
        case "graphic-media": return String(localized: "moderation.graphicMedia")
        case "gore":          return String(localized: "moderation.gore")
        default:              return val
        }
    }

    private func repostHeader(by profile: ProfileViewBasic?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.2.squarepath")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(profile?.displayNameOrHandle ?? "??")\(String(localized: "post.reposted"))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .padding(.leading, 56)
    }

    private var authorRow: some View {
        HStack(spacing: 4) {
            Button {
                onTapPost?(feedPost)
            } label: {
                HStack(spacing: 4) {
                    Text(author.displayNameOrHandle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    VerificationBadge(profile: author, size: 14)
                    if isBotAccount(did: author.did, labels: author.labels) {
                        BotBadge(size: 14)
                    }
                    Text("@\(author.handle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Text(relativeTime(from: post.indexedAt))
                .font(.caption)
                .foregroundStyle(.secondary)
            moreMenu
        }
    }

    @ViewBuilder
    private var moreMenu: some View {
        Menu {
            // 共有シート
            Button {
                let url = "https://bsky.app/profile/\(author.handle)/post/\(post.uri.components(separatedBy: "/").last ?? "")"
                sharePost(urlString: url)
            } label: {
                Label(String(localized: "post.share"), systemImage: "square.and.arrow.up")
            }

            // リンクをコピー
            Button {
                let url = "https://bsky.app/profile/\(author.handle)/post/\(post.uri.components(separatedBy: "/").last ?? "")"
                UIPasteboard.general.string = url
            } label: {
                Label(String(localized: "post.copyLink"), systemImage: "link")
            }

            // 翻訳する（外部ブラウザ）
            Button {
                let text = post.record.text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let langCode = Locale.current.language.languageCode?.identifier ?? "en"
                if let url = URL(string: "https://translate.google.com/?text=\(text)&sl=auto&tl=\(langCode)") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label(String(localized: "post.translate"), systemImage: "character.bubble")
            }

            // 画像・動画を保存（画像または動画が含まれる投稿のみ表示）
            if hasMediaToSave {
                Button {
                    Task { await saveMediaToPhotoLibrary() }
                } label: {
                    Label(String(localized: "post.saveMedia"), systemImage: "square.and.arrow.down")
                }
                .disabled(isSavingMedia)
            }

            // 他人の投稿のみ：非表示・通報・スレッドミュート・ミュート・ブロック・通報
            if let currentUserDID, currentUserDID != author.did {
                Divider()
                Button {
                    Task { await toggleHidePost() }
                } label: {
                    Label(String(localized: "post.hidePost"), systemImage: "eye.slash")
                }
                Button {
                    reportTarget = .post(uri: post.uri, cid: post.cid)
                } label: {
                    Label(String(localized: "post.reportPost"), systemImage: "flag")
                }
                Button {
                    Task { await toggleMuteThread() }
                } label: {
                    Label(
                        String(localized: isThreadMuted ? "post.unmuteThread" : "post.muteThread"),
                        systemImage: isThreadMuted ? "bell" : "bell.slash"
                    )
                }
                Divider()
                Button {
                    onTapMuteUser?(post)
                } label: {
                    let isMuted = post.author.viewer?.muted == true
                    Label(
                        String(localized: isMuted ? "post.unmuteUser" : "post.muteUser"),
                        systemImage: isMuted ? "speaker.wave.2" : "speaker.slash"
                    )
                }
                Button(role: post.author.viewer?.blocking != nil ? .none : .destructive) {
                    onTapBlockUser?(post)
                } label: {
                    let isBlocked = post.author.viewer?.blocking != nil
                    Label(
                        String(localized: isBlocked ? "post.unblockUser" : "post.blockUser"),
                        systemImage: isBlocked ? "hand.raised.slash" : "hand.raised"
                    )
                }
                Button(role: .destructive) {
                    reportTarget = .account(did: author.did)
                } label: {
                    Label(String(localized: "post.reportUser"), systemImage: "person.badge.minus")
                }
            }

            // 自分の投稿の場合のみ：スレッドミュート・削除
            if let currentUserDID, currentUserDID == author.did {
                Divider()
                Button {
                    Task { await toggleMuteThread() }
                } label: {
                    Label(
                        String(localized: isThreadMuted ? "post.unmuteThread" : "post.muteThread"),
                        systemImage: isThreadMuted ? "bell" : "bell.slash"
                    )
                }
                Divider()
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label(String(localized: "post.delete"), systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .padding(.leading, 4)
        }
        .buttonStyle(.plain)
    }

    private func replyIndicator(parentUri: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrowshape.turn.up.left")
                .font(.caption2)
            Text(String(localized: "compose.reply"))
                .font(.caption)
        }
        .foregroundStyle(.secondary)
    }

    /// メディアブラー対応の埋め込みコンテンツ表示
    @ViewBuilder
    private func moderatedEmbedView(_ embed: PostEmbed, moderation: ModerationResult) -> some View {
        if moderation.decision == .mediaBlur {
            ZStack {
                embedView(embed)
                MediaBlurOverlay(message: moderation.message)
            }
        } else {
            embedView(embed)
        }
    }

    private func embedView(_ embed: PostEmbed) -> some View {
        Group {
            switch embed {
            case .images(let images):
                ImageGridView(images: images.images)
            case .gallery(let gallery):
                if gallery.items.count <= 4 {
                    ImageGridView(images: gallery.items)
                } else {
                    GalleryCarouselView(images: gallery.items)
                }
            case .external(let ext):
                LinkCardView(external: ext.external)
            case .record(let record):
                if let rec = record.record {
                    QuoteEmbedView(record: rec)
                } else {
                    EmptyView()
                }
            case .recordWithMedia(let rwm):
                VStack(spacing: 6) {
                    if let media = rwm.media {
                        AnyView(embedView(media))
                    }
                    if let rec = rwm.record.record {
                        QuoteEmbedView(record: rec)
                    }
                }
            case .video(let video):
                VideoPlayerView(video: video)
            case .unknown:
                EmptyView()
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            // 返信
            actionButton(
                icon: "bubble.left",
                count: post.replyCount ?? 0,
                active: false,
                color: .secondary,
                action: {
                    if let onTapReply { onTapReply(post) } else { onTapPost?(feedPost) }
                },
                onTapCount: nil
            )

            Spacer()

            // リポスト（アイコン: トグル、数字: ユーザーリスト）
            actionButton(
                icon: "arrow.2.squarepath",
                count: repostCount,
                active: isReposted,
                color: .green,
                action: { Task { await toggleRepost() } },
                onTapCount: onTapRepostCount.map { cb in { cb(post) } }
            )

            Spacer()

            // いいね（アイコン: トグル、数字: ユーザーリスト）
            actionButton(
                icon: isLiked ? "heart.fill" : "heart",
                count: likeCount,
                active: isLiked,
                color: .red,
                action: { Task { await toggleLike() } },
                onTapCount: onTapLikeCount.map { cb in { cb(post) } }
            )

            Spacer()

            // 引用（メニュー：引用して投稿 / 引用一覧を見る）
            if onTapQuote != nil || onTapViewQuotes != nil {
                Menu {
                    if let onTapQuote {
                        Button {
                            onTapQuote(post)
                        } label: {
                            Label(String(localized: "post.quotePost"), systemImage: "quote.bubble")
                        }
                    }
                    if let onTapViewQuotes {
                        Button {
                            onTapViewQuotes(post)
                        } label: {
                            Label(String(localized: "post.viewQuotes"), systemImage: "list.bullet")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "quote.bubble")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                        let count = post.quoteCount ?? 0
                        if count > 0 {
                            Text(formatCount(count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // ブックマーク
            Button {
                Task { await toggleBookmark() }
            } label: {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 15))
                    .foregroundStyle(isBookmarked ? Color.orange : .secondary)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.top, 6)
    }

    private func actionButton(
        icon: String,
        count: Int,
        active: Bool,
        color: Color,
        action: @escaping () -> Void,
        onTapCount: (() -> Void)?
    ) -> some View {
        HStack(spacing: 4) {
            // アイコンボタン（メインアクション：トグルなど）
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(active ? color : .secondary)
            }
            .buttonStyle(.plain)

            // カウント数字（タップでユーザーリスト、コールバックなければアイコンと同じアクション）
            if count > 0 {
                if let onTapCount {
                    Button(action: onTapCount) {
                        Text(formatCount(count))
                            .font(.caption)
                            .foregroundStyle(active ? color : .secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: action) {
                        Text(formatCount(count))
                            .font(.caption)
                            .foregroundStyle(active ? color : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleLike() async {
        guard let postService else { return }
        if isLiked {
            // いいね取消（楽観的 UI）
            isLiked = false
            likeCount = max(0, likeCount - 1)
            let uri = likeUri
            likeUri = nil
            if let uri {
                try? await postService.unlike(likeUri: uri)
            }
        } else {
            // いいね（楽観的 UI）
            isLiked = true
            likeCount += 1
            do {
                let res = try await postService.like(uri: post.uri, cid: post.cid)
                likeUri = res.uri
            } catch {
                // ロールバック
                isLiked = false
                likeCount = max(0, likeCount - 1)
            }
        }
    }

    private func toggleRepost() async {
        guard let postService else { return }
        if isReposted {
            isReposted = false
            repostCount = max(0, repostCount - 1)
            let uri = repostUri
            repostUri = nil
            if let uri {
                try? await postService.unrepost(repostUri: uri)
            }
        } else {
            isReposted = true
            repostCount += 1
            do {
                let res = try await postService.repost(uri: post.uri, cid: post.cid)
                repostUri = res.uri
            } catch {
                isReposted = false
                repostCount = max(0, repostCount - 1)
            }
        }
    }

    private func toggleBookmark() async {
        guard let postService else { return }
        if isBookmarked {
            isBookmarked = false
            try? await postService.unbookmark(uri: post.uri)
            onUnbookmark?(post)
        } else {
            isBookmarked = true
            do {
                try await postService.bookmark(uri: post.uri, cid: post.cid)
            } catch {
                isBookmarked = false
            }
        }
    }

    private func toggleHidePost() async {
        guard let postService else { return }
        try? await postService.hidePost(uri: post.uri)
        onDelete?(post)
    }

    private func toggleMuteThread() async {
        guard let postService else { return }
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

    private func deletePost() async {
        guard let postService else { return }
        do {
            try await postService.deletePost(uri: post.uri)
            onDelete?(post)
        } catch {
            // 削除失敗は無視（UIフィードバックは将来的にアラートで対応）
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

    // MARK: - メディア保存

    private var hasMediaToSave: Bool { MediaSaveHelper.hasMedia(in: post.embed) }

    private func saveMediaToPhotoLibrary() async {
        isSavingMedia = true
        let count = await MediaSaveHelper.save(embed: post.embed)
        isSavingMedia = false
        let msg = count > 0
            ? String(localized: "media.saveSuccess")
            : String(localized: "media.saveFailed")
        withAnimation { saveToastMessage = msg }
        try? await Task.sleep(for: .seconds(2))
        withAnimation { saveToastMessage = nil }
    }

    // MARK: - Helpers

    private func relativeTime(from dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateString) ?? ISO8601DateFormatter().date(from: dateString) else {
            return ""
        }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: date, relativeTo: Date())
    }

    private func formatCount(_ count: Int) -> String {
        count >= 1000 ? String(format: "%.1fK", Double(count) / 1000) : "\(count)"
    }

    // MARK: - BSAF ヘルパービュー

    /// BSAF タグバッジ表示（WrappingHStack でモノスペースバッジ）
    @ViewBuilder
    private func bsafTagsRow(tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            WrappingHStack(alignment: .leading, spacing: 4) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .padding(.top, 4)
    }

    /// BSAF 重複投稿インジケーター（「他N件のBotも報告」）
    @ViewBuilder
    private func bsafDuplicateRow(count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(String(localized: "bsaf.duplicateReport \(count)"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}


