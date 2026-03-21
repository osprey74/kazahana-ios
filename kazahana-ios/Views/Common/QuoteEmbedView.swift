// QuoteEmbedView.swift
// kazahana-ios
// 引用リポストの埋め込み表示

import SwiftUI

struct QuoteEmbedView: View {

    let record: EmbedRecordView

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
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}
