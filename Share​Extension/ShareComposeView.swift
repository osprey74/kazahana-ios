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

                // 文字数カウンター・via 表示
                HStack {
                    if let via = ShareSettings.via {
                        Text("via \(via)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
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

        var images: [UIImage] = []
        var url: URL? = nil
        var pageTitle: String? = nil

        for item in items {
            // attributedTitle からページタイトルを取得
            if let title = item.attributedTitle?.string, !title.isEmpty {
                pageTitle = title
            }

            // attributedContentText: macOS Safari はここに URL を格納することがある
            if let contentText = item.attributedContentText?.string {
                let trimmed = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let parsedURL = URL(string: trimmed), parsedURL.scheme?.hasPrefix("http") == true {
                    url = parsedURL
                } else if pageTitle == nil, !trimmed.isEmpty {
                    pageTitle = trimmed
                }
            }

            // attachments から URL・画像を取得
            // ObjC コールバック形式が macOS Catalyst で安定して動作する
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                // URL（public.url 型）
                // macOS Catalyst では NSURL でなく NSData（UTF-8バイト列）で返ることがある
                if url == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    let candidate: URL? = await withCheckedContinuation { continuation in
                        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                            if let nsURL = item as? NSURL {
                                continuation.resume(returning: nsURL as URL)
                            } else if let data = item as? NSData,
                                      let str = String(data: data as Data, encoding: .utf8),
                                      let parsed = URL(string: str.trimmingCharacters(in: .whitespacesAndNewlines)) {
                                continuation.resume(returning: parsed)
                            } else if let str = (item as? NSString) as String?,
                                      let parsed = URL(string: str.trimmingCharacters(in: .whitespacesAndNewlines)) {
                                continuation.resume(returning: parsed)
                            } else {
                                continuation.resume(returning: nil)
                            }
                        }
                    }
                    if let candidate, candidate.scheme?.hasPrefix("http") == true {
                        url = candidate
                    }
                }
                // plain-text フォールバック
                if url == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    let str: String? = await withCheckedContinuation { continuation in
                        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                            let s = (item as? NSString).map { $0 as String } ?? (item as? String)
                            continuation.resume(returning: s)
                        }
                    }
                    if let str,
                       let parsedURL = URL(string: str.trimmingCharacters(in: .whitespacesAndNewlines)),
                       parsedURL.scheme?.hasPrefix("http") == true {
                        url = parsedURL
                    }
                }
                // 画像（最大4枚）
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier), images.count < 4 {
                    let img: UIImage? = await withCheckedContinuation { continuation in
                        provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, _ in
                            if let image = item as? UIImage {
                                continuation.resume(returning: image)
                            } else if let imgURL = item as? URL,
                                      let data = try? Data(contentsOf: imgURL),
                                      let image = UIImage(data: data) {
                                continuation.resume(returning: image)
                            } else {
                                continuation.resume(returning: nil)
                            }
                        }
                    }
                    if let img { images.append(img) }
                }
            }
        }

        await MainActor.run {
            if let u = url {
                if let title = pageTitle {
                    text = title + "\n" + u.absoluteString
                } else {
                    text = u.absoluteString
                }
                sharedURL = u
            }
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
                // macOS Safari は attributedTitle が nil のため OGP タイトルで text を補完
                if !card.title.isEmpty, text == url.absoluteString {
                    text = card.title + "\n" + url.absoluteString
                }
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
