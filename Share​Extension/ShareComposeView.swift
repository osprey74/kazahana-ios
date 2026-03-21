// ShareComposeView.swift
// Share​Extension
// 共有シートから受け取ったコンテンツを Bluesky に投稿するための軽量 UI

import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Bundle helper

/// Share Extension は独立したバンドルなので .module を使う
private let extensionBundle = Bundle(for: ShareViewController.self)

private func shareLocalized(_ key: String) -> String {
    NSLocalizedString(key, bundle: extensionBundle, comment: "")
}

// MARK: - リンクカードプレビューモデル

struct LinkCardPreview {
    let url: URL
    let title: String
    let description: String
    let thumbURL: URL?
    let card: ExternalCard
}

// MARK: - メインビュー

struct ShareComposeView: View {

    let extensionContext: NSExtensionContext?
    let session: Session?

    @State private var text: String = ""
    @State private var sharedImages: [UIImage] = []
    @State private var sharedURL: URL? = nil
    @State private var linkCardPreview: LinkCardPreview? = nil
    @State private var isFetchingCard = false
    @State private var isPosting = false
    @State private var errorMessage: String? = nil
    @State private var isLoaded = false

    private let maxLength = 300
    private var remaining: Int { maxLength - graphemeCount(text) }

    var body: some View {
        NavigationStack {
            Group {
                if session == nil {
                    notLoggedInView
                } else {
                    composeBody
                }
            }
            .navigationTitle(shareLocalized("share.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(shareLocalized("compose.cancel")) {
                        extensionContext?.cancelRequest(withError: NSError(domain: "kazahana", code: 0))
                    }
                }
                if session != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(shareLocalized("compose.post")) {
                            Task { await post() }
                        }
                        .disabled(isPosting || remaining < 0 || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && sharedImages.isEmpty))
                        .bold()
                    }
                }
            }
        }
        .task { await loadSharedContent() }
        .overlay {
            if isPosting {
                postingOverlay
            }
        }
    }

    // MARK: - 未ログイン表示

    private var notLoggedInView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(shareLocalized("share.notLoggedIn"))
                .font(.headline)
            Text(shareLocalized("share.notLoggedInMessage"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 投稿フォーム

    private var composeBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // テキストエディタ
                TextEditor(text: $text)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)

                Divider()

                // 文字数カウンター
                HStack {
                    Spacer()
                    Text("\(remaining)")
                        .font(.caption)
                        .foregroundStyle(remaining < 0 ? .red : remaining < 20 ? .orange : .secondary)
                }

                // リンクカードプレビュー（画像がない場合のみ）
                if sharedImages.isEmpty {
                    if isFetchingCard {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(sharedURL?.host ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else if let preview = linkCardPreview {
                        LinkCardPreviewView(preview: preview)
                    } else if let url = sharedURL {
                        // OGP 取得失敗時はシンプル表示
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(url.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                // 画像プレビュー
                if !sharedImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(sharedImages.enumerated()), id: \.offset) { _, img in
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }

                // エラー表示
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 4)
                }
            }
            .padding()
        }
    }

    // MARK: - 投稿中オーバーレイ

    private var postingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            ProgressView()
                .tint(.white)
                .scaleEffect(1.5)
        }
    }

    // MARK: - 共有コンテンツ読み込み

    private func loadSharedContent() async {
        guard !isLoaded else { return }
        isLoaded = true

        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }

        var texts: [String] = []
        var images: [UIImage] = []
        var url: URL? = nil

        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                // URL
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let loaded = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier),
                       let loadedURL = loaded as? URL {
                        url = loadedURL
                    }
                }
                // テキスト
                else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let loaded = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier),
                       let str = loaded as? String {
                        texts.append(str)
                    }
                }
                // 画像（最大4枚）
                else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier), images.count < 4 {
                    if let loaded = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) {
                        if let img = loaded as? UIImage {
                            images.append(img)
                        } else if let imgURL = loaded as? URL,
                                  let data = try? Data(contentsOf: imgURL),
                                  let img = UIImage(data: data) {
                            images.append(img)
                        }
                    }
                }
            }
        }

        await MainActor.run {
            // テキストと URL を結合
            var combined = texts.joined(separator: "\n")
            if let u = url {
                if !combined.isEmpty { combined += "\n" }
                combined += u.absoluteString
                sharedURL = u
            }
            text = combined
            sharedImages = images
        }

        // URL があり画像がない場合は OGP を取得してリンクカードを生成
        if let url, images.isEmpty, let session {
            await fetchLinkCardPreview(url: url, session: session)
        }
    }

    // MARK: - OGP 取得

    private func fetchLinkCardPreview(url: URL, session: Session) async {
        await MainActor.run { isFetchingCard = true }
        let client = ShareATProtoClient(session: session)
        do {
            let card = try await client.fetchLinkCard(url: url)
            let thumbURL: URL? = nil  // OGP image は既にアップロード済み（BlobRef に変換）
            let preview = LinkCardPreview(
                url: url,
                title: card.title,
                description: card.description,
                thumbURL: thumbURL,
                card: card
            )
            await MainActor.run {
                linkCardPreview = preview
                isFetchingCard = false
            }
        } catch {
            await MainActor.run { isFetchingCard = false }
        }
    }

    // MARK: - 投稿実行

    private func post() async {
        guard let session else { return }
        isPosting = true
        errorMessage = nil

        do {
            let client = ShareATProtoClient(session: session)

            // 画像アップロード
            var uploadedImages: [(blob: BlobRef, alt: String)] = []
            for img in sharedImages {
                let compressed = compressImage(img)
                let blob = try await client.uploadImage(data: compressed, mimeType: "image/jpeg")
                uploadedImages.append((blob: blob, alt: ""))
            }

            // Facet 検出
            let facets = ShareATProtoClient.detectFacets(in: text)

            // リンクカード（画像がない場合のみ）
            let linkCard: ExternalCard? = uploadedImages.isEmpty ? linkCardPreview?.card : nil

            // langs / via
            let langs = ShareSettings.langs
            let via = ShareSettings.via

            // 投稿
            _ = try await client.createPost(
                text: text,
                facets: facets.isEmpty ? nil : facets,
                images: uploadedImages.isEmpty ? nil : uploadedImages,
                linkCard: linkCard,
                langs: langs,
                via: via
            )

            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        } catch {
            await MainActor.run {
                errorMessage = shareLocalized("compose.error") + "\n" + error.localizedDescription
                isPosting = false
            }
        }
    }

    // MARK: - 画像圧縮

    /// JPEG 圧縮・最大辺 2048px にリサイズ（950KB 以内）
    private func compressImage(_ image: UIImage) -> Data {
        let maxSize: CGFloat = 2048
        var img = image

        // リサイズ
        let size = img.size
        if size.width > maxSize || size.height > maxSize {
            let scale = maxSize / max(size.width, size.height)
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            img = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        }

        // 圧縮（950KB 以内）
        var quality: CGFloat = 0.9
        var data = img.jpegData(compressionQuality: quality) ?? Data()
        while data.count > 950_000 && quality > 0.1 {
            quality -= 0.1
            data = img.jpegData(compressionQuality: quality) ?? data
        }
        return data
    }

    // MARK: - ユーティリティ

    private func graphemeCount(_ str: String) -> Int {
        str.unicodeScalars.reduce(0) { $0 + ($1.utf16.count > 0 ? 1 : 0) }
    }
}

// MARK: - リンクカードプレビューUI

private struct LinkCardPreviewView: View {
    let preview: LinkCardPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(preview.url.host ?? preview.url.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !preview.title.isEmpty {
                Text(preview.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(2)
            }
            if !preview.description.isEmpty {
                Text(preview.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
