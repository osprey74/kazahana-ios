// LinkCardView.swift
// kazahana-ios
// 外部リンクカード（OGPプレビュー）

import SwiftUI

struct LinkCardView: View {

    let external: ExternalView

    var body: some View {
        Link(destination: URL(string: external.uri) ?? URL(string: "https://bsky.app")!) {
            HStack(spacing: 0) {
                // サムネイル
                if let thumb = external.thumb, let thumbURL = URL(string: thumb) {
                    AsyncImage(url: thumbURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Rectangle().fill(Color.secondary.opacity(0.2))
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipped()
                }

                // テキスト情報
                VStack(alignment: .leading, spacing: 4) {
                    Text(external.title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(2)
                        .foregroundStyle(.primary)

                    if let desc = external.description, !desc.isEmpty {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Text(hostName(from: external.uri))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func hostName(from urlString: String) -> String {
        URL(string: urlString)?.host ?? urlString
    }
}
