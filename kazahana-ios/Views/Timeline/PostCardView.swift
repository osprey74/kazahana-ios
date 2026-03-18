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
    /// 引用投稿ボタンタップ
    var onTapQuote: ((PostView) -> Void)?

    // ローカル状態（楽観的 UI 更新用）
    @State private var isLiked: Bool
    @State private var likeCount: Int
    @State private var isReposted: Bool
    @State private var repostCount: Int
    @State private var likeUri: String?
    @State private var repostUri: String?

    private var post: PostView { feedPost.post }
    private var author: ProfileViewBasic { post.author }

    init(
        feedPost: FeedViewPost,
        postService: PostService? = nil,
        onTapPost: ((FeedViewPost) -> Void)? = nil,
        onTapAuthor: ((String) -> Void)? = nil,
        onTapReply: ((PostView) -> Void)? = nil,
        onTapLikeCount: ((PostView) -> Void)? = nil,
        onTapRepostCount: ((PostView) -> Void)? = nil,
        onTapQuote: ((PostView) -> Void)? = nil
    ) {
        self.feedPost = feedPost
        self.postService = postService
        self.onTapPost = onTapPost
        self.onTapAuthor = onTapAuthor
        self.onTapReply = onTapReply
        self.onTapLikeCount = onTapLikeCount
        self.onTapRepostCount = onTapRepostCount
        self.onTapQuote = onTapQuote
        _isLiked     = State(initialValue: feedPost.post.viewer?.like != nil)
        _likeCount   = State(initialValue: feedPost.post.likeCount ?? 0)
        _isReposted  = State(initialValue: feedPost.post.viewer?.repost != nil)
        _repostCount = State(initialValue: feedPost.post.repostCount ?? 0)
        _likeUri     = State(initialValue: feedPost.post.viewer?.like)
        _repostUri   = State(initialValue: feedPost.post.viewer?.repost)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // リポストヘッダー
            if let reason = feedPost.reason, reason.type == "app.bsky.feed.defs#reasonRepost" {
                repostHeader(by: reason.by)
            }

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
                            // kazahana:// スキームは内部遷移（将来対応）
                            return .systemAction
                        })
                    }

                    // 埋め込みコンテンツ
                    if let embed = post.embed {
                        embedView(embed)
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

            Divider()
        }
    }

    // MARK: - Subviews

    private func repostHeader(by profile: ProfileViewBasic?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.2.squarepath")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(profile?.displayNameOrHandle ?? "誰か")がリポスト")
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
            Text(author.displayNameOrHandle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text("@\(author.handle)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(relativeTime(from: post.indexedAt))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func replyIndicator(parentUri: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrowshape.turn.up.left")
                .font(.caption2)
            Text("返信")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
    }

    private func embedView(_ embed: PostEmbed) -> some View {
        Group {
            switch embed {
            case .images(let images):
                ImageGridView(images: images.images)
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

            // 引用投稿
            if let onTapQuote {
                Button {
                    onTapQuote(post)
                } label: {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

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

    // MARK: - Helpers

    private func relativeTime(from dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateString) ?? ISO8601DateFormatter().date(from: dateString) else {
            return ""
        }
        let diff = Date().timeIntervalSince(date)
        switch diff {
        case ..<60:     return "\(Int(diff))秒"
        case ..<3600:   return "\(Int(diff / 60))分"
        case ..<86400:  return "\(Int(diff / 3600))時間"
        default:
            let cal = Calendar.current
            let c = cal.dateComponents([.month, .year], from: date, to: Date())
            if let y = c.year, y > 0 { return "\(y)年前" }
            if let m = c.month, m > 0 { return "\(m)ヶ月前" }
            return "\(Int(diff / 86400))日前"
        }
    }

    private func formatCount(_ count: Int) -> String {
        count >= 1000 ? String(format: "%.1fK", Double(count) / 1000) : "\(count)"
    }
}


