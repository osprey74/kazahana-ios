// LinkCardView.swift
// kazahana-ios
// 外部リンクカード（OGPプレビュー / Standard Site 拡張リンクカード）

import SwiftUI

struct LinkCardView: View {

    let external: ExternalView
    var hideSubscribe: Bool = false

    /// Standard Site の source が存在するかで拡張カード判定
    private var hasSource: Bool { external.source != nil }

    /// 著者情報（associatedProfiles の先頭）
    private var author: ProfileViewBasic? { external.associatedProfiles?.first }

    /// publication 単独カード（記事タイトルが空 or URI が publication の URI と一致）
    private var isPublicationOnly: Bool {
        guard let source = external.source else { return false }
        return external.title.isEmpty || external.uri == source.uri
    }

    var body: some View {
        if isPublicationOnly, let source = external.source {
            publicationOnlyCard(source: source)
        } else if hasSource {
            documentWithPublicationCard
        } else {
            classicCard
        }
    }

    // MARK: - パターン1: 従来のリンクカード（Standard Site 非対応）

    private var classicCard: some View {
        Link(destination: URL(string: external.uri) ?? URL(string: "https://bsky.app")!) {
            HStack(spacing: 0) {
                if let thumb = external.thumb, let thumbURL = URL(string: thumb) {
                    thumbnailImage(url: thumbURL)
                }

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
            .cardBackground()
        }
        .buttonStyle(.plain)
    }

    // MARK: - パターン2: document + publication カード

    private var documentWithPublicationCard: some View {
        VStack(spacing: 0) {
            // 記事部分
            Link(destination: URL(string: external.uri) ?? URL(string: "https://bsky.app")!) {
                HStack(spacing: 0) {
                    if let thumb = external.thumb, let thumbURL = URL(string: thumb) {
                        thumbnailImage(url: thumbURL)
                    }

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

                        metadataRow
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)

            // パブリケーション情報
            if let source = external.source {
                Divider()
                    .padding(.horizontal, 10)

                publicationSection(source: source)
            }
        }
        .frame(maxWidth: .infinity)
        .cardBackground()
    }

    // MARK: - パターン3: publication 単独カード

    private func publicationOnlyCard(source: ExternalSource) -> some View {
        Link(destination: URL(string: source.uri) ?? URL(string: "https://bsky.app")!) {
            HStack(spacing: 10) {
                // パブリケーションアイコン
                if let icon = source.icon, let iconURL = URL(string: icon) {
                    AsyncImage(url: iconURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.2))
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(source.title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    if let desc = source.description, !desc.isEmpty {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if let author = author {
                        Text(String(localized: "linkCard.author \(author.handle)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !hideSubscribe {
                    subscribeButton(source: source)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .cardBackground()
        }
        .buttonStyle(.plain)
    }

    // MARK: - 共通コンポーネント

    /// サムネイル画像
    private func thumbnailImage(url: URL) -> some View {
        AsyncImage(url: url) { phase in
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

    /// 公開日・読了時間のメタデータ行
    private var metadataRow: some View {
        HStack(spacing: 8) {
            Text(hostName(from: external.uri))
                .font(.caption)
                .foregroundStyle(.tertiary)

            if let readingTime = external.readingTime, readingTime > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("\(readingTime)m")
                        .font(.caption)
                }
                .foregroundStyle(.tertiary)
            }

            if let createdAt = external.createdAt {
                Text(formatDate(createdAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// パブリケーション情報セクション（document + publication カード内）
    private func publicationSection(source: ExternalSource) -> some View {
        Link(destination: URL(string: source.uri) ?? URL(string: "https://bsky.app")!) {
            HStack(spacing: 8) {
                if let icon = source.icon, let iconURL = URL(string: icon) {
                    AsyncImage(url: iconURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.2))
                        }
                    }
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let author = author {
                        Text(String(localized: "linkCard.author \(author.handle)"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if !hideSubscribe {
                    subscribeButton(source: source)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    /// 購読ボタン（テーマカラー適用）
    private func subscribeButton(source: ExternalSource) -> some View {
        Text(String(localized: "linkCard.viewPublication"))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(accentForegroundColor(for: source))
            .background(accentColor(for: source))
            .clipShape(Capsule())
    }

    // MARK: - テーマカラー

    private func accentColor(for source: ExternalSource) -> Color {
        if let rgb = source.theme?.accentRGB {
            return Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
        }
        return .accentColor
    }

    private func accentForegroundColor(for source: ExternalSource) -> Color {
        if let rgb = source.theme?.accentForegroundRGB {
            return Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
        }
        return .white
    }

    // MARK: - ヘルパー

    private func hostName(from urlString: String) -> String {
        URL(string: urlString)?.host ?? urlString
    }

    private func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: isoString) {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        // fractionalSeconds なしでもリトライ
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: isoString) {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        return ""
    }
}

// MARK: - カード背景モディファイア

private extension View {
    func cardBackground() -> some View {
        self
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
    }
}
