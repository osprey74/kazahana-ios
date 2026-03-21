import SwiftUI

struct NotificationItemView: View {
    let notification: AppNotification
    var subjectPost: PostView? = nil
    var postService: PostService? = nil
    var onTapAuthor: ((String) -> Void)? = nil
    var onTapReply: ((PostView) -> Void)? = nil

    // いいね/リポストの楽観的UI状態
    @State private var isLiked = false
    @State private var likeCount = 0
    @State private var likeUri: String? = nil
    @State private var isReposted = false
    @State private var repostCount = 0
    @State private var repostUri: String? = nil
    @State private var initialized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ── ヘッダー行：アバター＋アクションアイコン＋理由テキスト ──
            HStack(alignment: .top, spacing: 10) {
                // アバター（タップでプロフィール）
                Button {
                    onTapAuthor?(notification.author.did)
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        AvatarView(url: notification.author.avatar, size: 40)
                        Image(systemName: notification.reasonIcon)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(notification.reasonColor, in: Circle())
                            .offset(x: 3, y: 3)
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    // ユーザー名（タップでプロフィール）
                    Button {
                        onTapAuthor?(notification.author.did)
                    } label: {
                        HStack(spacing: 4) {
                            Text(notification.author.displayName ?? notification.author.handle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if isBotAccount(did: notification.author.did, labels: notification.author.labels) {
                                BotBadge(size: 13)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Text(notification.reasonLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    // 未読インジケーター
                    if !notification.isRead {
                        Circle()
                            .fill(.blue)
                            .frame(width: 8, height: 8)
                    }
                    Text(notification.indexedAt.relativeFormatted)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // ── 投稿コンテンツ（like/repost/reply/mention/quote） ──
            if let post = subjectPost {
                postContentView(post)
            } else if notification.reason == "reply" || notification.reason == "mention" || notification.reason == "quote" {
                // fetchSubjectPosts が間に合わない場合は record.text で代替表示
                if let text = notification.record.text, !text.isEmpty {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .padding(.leading, 50)
                }
            }
        }
        .padding(.vertical, 6)
        .opacity(notification.isRead ? 0.85 : 1.0)
        .task(id: subjectPost?.uri) {
            if !initialized, let post = subjectPost {
                isLiked    = post.viewer?.like != nil
                likeCount  = post.likeCount ?? 0
                likeUri    = post.viewer?.like
                isReposted = post.viewer?.repost != nil
                repostCount = post.repostCount ?? 0
                repostUri  = post.viewer?.repost
                initialized = true
            }
        }
    }

    // MARK: - 投稿コンテンツビュー

    @ViewBuilder
    private func postContentView(_ post: PostView) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // 本文
            if !post.record.text.isEmpty {
                Text(post.record.text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // アクションバー（返信・リポスト・いいね）
            HStack(spacing: 0) {
                // 返信ボタン
                actionIcon(
                    icon: "bubble.left",
                    count: post.replyCount ?? 0,
                    color: .secondary
                ) { onTapReply?(post) }

                Spacer()

                // リポスト
                actionIcon(
                    icon: "arrow.2.squarepath",
                    count: repostCount,
                    color: isReposted ? .green : .secondary
                ) {
                    Task { await toggleRepost(post: post) }
                }

                Spacer()

                // いいね
                actionIcon(
                    icon: isLiked ? "heart.fill" : "heart",
                    count: likeCount,
                    color: isLiked ? .red : .secondary
                ) {
                    Task { await toggleLike(post: post) }
                }

                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .padding(.leading, 50)
    }

    @ViewBuilder
    private func actionIcon(icon: String, count: Int, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                if count > 0 {
                    Text("\(count)")
                        .font(.caption)
                }
            }
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }

    // MARK: - いいね/リポスト

    private func toggleLike(post: PostView) async {
        guard let postService else { return }
        let prev = (isLiked, likeCount, likeUri)
        if isLiked, let uri = likeUri {
            isLiked = false; likeCount -= 1; likeUri = nil
            do { try await postService.unlike(likeUri: uri) }
            catch { isLiked = prev.0; likeCount = prev.1; likeUri = prev.2 }
        } else {
            isLiked = true; likeCount += 1
            do {
                let res = try await postService.like(uri: post.uri, cid: post.cid)
                likeUri = res.uri
            } catch { isLiked = prev.0; likeCount = prev.1; likeUri = prev.2 }
        }
    }

    private func toggleRepost(post: PostView) async {
        guard let postService else { return }
        let prev = (isReposted, repostCount, repostUri)
        if isReposted, let uri = repostUri {
            isReposted = false; repostCount -= 1; repostUri = nil
            do { try await postService.unrepost(repostUri: uri) }
            catch { isReposted = prev.0; repostCount = prev.1; repostUri = prev.2 }
        } else {
            isReposted = true; repostCount += 1
            do {
                let res = try await postService.repost(uri: post.uri, cid: post.cid)
                repostUri = res.uri
            } catch { isReposted = prev.0; repostCount = prev.1; repostUri = prev.2 }
        }
    }
}
