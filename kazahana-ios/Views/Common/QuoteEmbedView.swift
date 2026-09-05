// QuoteEmbedView.swift
// kazahana-ios
// 引用リポストの埋め込み表示

import SwiftUI

struct QuoteEmbedView: View {

    let record: EmbedRecordView
    var onTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let author = record.author {
                HStack(spacing: 6) {
                    AvatarView(url: author.avatar, size: 18)
                    Text(author.displayNameOrHandle)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    if isBotAccount(did: author.did, labels: author.labels) {
                        BotBadge(size: 12)
                    }
                    Text("@\(author.handle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let text = record.value?.text, !text.isEmpty {
                Text(text)
                    .font(.caption)
                    .lineLimit(4)
                    .foregroundStyle(.primary)
            }

            // 引用元投稿の埋め込みメディア（画像・動画・リンクカード）
            if let embed = record.embeds?.first {
                quoteMediaView(embed)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }

    /// 引用投稿内の埋め込みメディアをコンパクト表示
    @ViewBuilder
    private func quoteMediaView(_ embed: PostEmbed) -> some View {
        switch embed {
        case .images(let images):
            quoteImageThumbnails(images.images)
        case .gallery(let gallery):
            quoteImageThumbnails(gallery.items)
        case .video(let video):
            VideoPlayerView(video: video, thumbnailOnly: true)
                .frame(maxHeight: 200)
        case .external(let ext):
            LinkCardView(external: ext.external)
        default:
            EmptyView()
        }
    }

    /// 引用投稿内の画像サムネイル（最大4枚）
    @ViewBuilder
    private func quoteImageThumbnails(_ images: [EmbedImageView]) -> some View {
        HStack(spacing: 4) {
            ForEach(images.prefix(4)) { image in
                AsyncImage(url: URL(string: image.thumb)) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        Color.secondary.opacity(0.2)
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}
