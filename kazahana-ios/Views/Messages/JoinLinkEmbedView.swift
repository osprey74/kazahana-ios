// JoinLinkEmbedView.swift
// kazahana-ios
// チャット内の招待リンクカード表示

import SwiftUI

struct JoinLinkEmbedView: View {
    let embed: JoinLinkEmbedData

    var body: some View {
        // Phase 1 では表示のみ（タップでの参加は Phase 2）
        Group {
            if let preview = embed.joinLinkPreview {
                switch preview {
                case .active(let active):
                    activeCard(active)
                case .disabled:
                    disabledCard(message: String(localized: "dm.joinLink.disabled"))
                case .invalid:
                    disabledCard(message: String(localized: "dm.joinLink.invalid"))
                }
            }
        }
    }

    @ViewBuilder
    private func activeCard(_ preview: JoinLinkPreviewActive) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.3.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text(String(localized: "dm.joinLink.label"))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
            }

            if let name = preview.name {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                if let owner = preview.owner {
                    AvatarView(url: owner.avatar, size: 20)
                    Text(String(localized: "dm.joinLink.ownerLabel \(owner.displayNameOrHandle)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let count = preview.memberCount {
                    Text(String(localized: "dm.joinLink.memberCount \(count)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func disabledCard(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "link.badge.plus")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6).opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}
