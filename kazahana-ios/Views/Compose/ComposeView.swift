// ComposeView.swift
// kazahana-ios
// 投稿作成画面（新規投稿・リプライ・引用・画像・動画添付対応）

import SwiftUI
import PhotosUI
import UIKit
import AVKit

struct SelectedImage: Identifiable {
    let id = UUID()
    var image: UIImage   // クロップ後の置き換えを可能にするため var
    var alt: String = ""
}

struct SelectedVideo: Identifiable {
    let id = UUID()
    let url: URL
    let data: Data
    let mimeType: String
    let thumbnail: UIImage?
    var alt: String = ""
}

struct ComposeView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var appSettings

    // テキストは View の @State で直接管理（@Observable ViewModel の TextEditor バインディング問題を回避）
    @State private var text: String = ""
    @State private var isPosting = false
    @State private var errorMessage: String? = nil

    // 画像添付
    @State private var selectedImages: [SelectedImage] = []
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var editingAltIndex: Int? = nil
    @State private var altText: String = ""
    @State private var isGeneratingAlt = false
    @State private var altGenerationError: String? = nil
    @State private var croppingImageIndex: Int? = nil  // クロップエディタ表示中の画像インデックス

    // 動画添付
    @State private var selectedVideo: SelectedVideo? = nil
    @State private var videoPickerItem: PhotosPickerItem? = nil

    // メンションオートコンプリート
    @State private var mentionCandidates: [ProfileViewBasic] = []
    @State private var mentionQuery: String? = nil   // nil = 非アクティブ
    @State private var mentionSearchTask: Task<Void, Never>? = nil
    // 解決済みメンション DID（handle → did のキャッシュ）
    @State private var resolvedMentions: [String: String] = [:]

    private let postService: PostService
    private let searchService: SearchService
    private let replyToPost: PostView?
    private let replyTarget: ReplyTarget?
    private let quotePost: PostView?

    init(postService: PostService, searchService: SearchService? = nil, replyTo: PostView? = nil, quotedPost: PostView? = nil) {
        self.postService = postService
        self.searchService = searchService ?? SearchService(client: postService.atProtoClient)
        self.replyToPost = replyTo
        self.quotePost = quotedPost
        if let replyTo {
            self.replyTarget = ReplyTarget(
                rootUri: replyTo.uri,
                rootCid: replyTo.cid,
                parentUri: replyTo.uri,
                parentCid: replyTo.cid
            )
        } else {
            self.replyTarget = nil
        }
    }

    private var graphemeCount: Int { text.count }
    private var remaining: Int { 300 - graphemeCount }
    private var canPost: Bool { (graphemeCount > 0 || !selectedImages.isEmpty || selectedVideo != nil) && remaining >= 0 && !isPosting }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 返信先・引用元プレビュー（上部に統一表示）
                if let replyTo = replyToPost {
                    referencePreview(post: replyTo, label: String(localized: "compose.replyPreview"))
                    Divider()
                } else if let quoted = quotePost {
                    referencePreview(post: quoted, label: String(localized: "compose.quotePreview"))
                    Divider()
                }

                // 入力エリア + メンション候補オーバーレイ
                ZStack(alignment: .bottom) {
                    TextEditor(text: $text)
                        .font(.body)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 12)
                        .scrollContentBackground(.hidden)
                        .onChange(of: text) { _, newValue in
                            updateMentionQuery(text: newValue)
                        }

                    // メンション候補リスト
                    if !mentionCandidates.isEmpty {
                        mentionSuggestionList
                    }
                }

                // 画像プレビュー
                if !selectedImages.isEmpty {
                    Divider()
                    imagePreviewRow
                }

                // 動画プレビュー
                if let video = selectedVideo {
                    Divider()
                    videoPreviewRow(video: video)
                }

                // 文字数インジケーター
                HStack {
                    Spacer()
                    characterCounter
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                Divider()
                bottomBar
            }
            .navigationTitle(replyToPost != nil ? String(localized: "compose.reply") : quotePost != nil ? String(localized: "compose.quotePost") : String(localized: "compose.newPost"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "compose.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "compose.post")) {
                        Task { await submitPost() }
                    }
                    .fontWeight(.bold)
                    .disabled(!canPost)
                }
            }
            .alert(String(localized: "compose.error"), isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button(String(localized: "compose.ok")) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            // Alt テキスト入力シート
            .sheet(isPresented: Binding(
                get: { editingAltIndex != nil },
                set: { if !$0 { editingAltIndex = nil } }
            )) {
                altEditSheet
            }
            // 画像クロップエディタ
            .fullScreenCover(isPresented: Binding(
                get: { croppingImageIndex != nil },
                set: { if !$0 { croppingImageIndex = nil } }
            )) {
                if let idx = croppingImageIndex, idx < selectedImages.count {
                    ImageCropView(image: selectedImages[idx].image) { croppedImage in
                        selectedImages[idx].image = croppedImage
                    }
                }
            }
            .onChange(of: photoPickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task { await loadPickedImages(items: newItems) }
            }
            .onChange(of: videoPickerItem) { _, newItem in
                guard let newItem else { return }
                Task { await loadPickedVideo(item: newItem) }
            }
            .overlay {
                if isPosting {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }
        }
    }

    // MARK: - Actions

    private func submitPost() async {
        guard canPost else { return }
        isPosting = true
        errorMessage = nil

        do {
            // 画像をアップロード（1MB 超の場合は自動圧縮・リサイズ）
            var uploadedImages: [(blob: BlobRef, alt: String)] = []
            for selected in selectedImages {
                guard let (imageData, mimeType) = compressImage(selected.image) else { continue }
                let blob = try await postService.uploadImage(data: imageData, mimeType: mimeType)
                uploadedImages.append((blob: blob, alt: selected.alt))
            }

            // 動画をアップロード
            var uploadedVideo: (blob: BlobRef, alt: String?, aspectRatio: AspectRatioCreate?)? = nil
            if let video = selectedVideo {
                let blob = try await postService.uploadVideo(data: video.data, mimeType: video.mimeType)
                let aspectRatio: AspectRatioCreate?
                if let thumb = video.thumbnail {
                    let w = Int(thumb.size.width)
                    let h = Int(thumb.size.height)
                    aspectRatio = (w > 0 && h > 0) ? AspectRatioCreate(width: w, height: h) : nil
                } else {
                    aspectRatio = nil
                }
                uploadedVideo = (blob: blob, alt: video.alt.isEmpty ? nil : video.alt, aspectRatio: aspectRatio)
            }

            let detected = RichTextParser.detectFacets(in: text)
            let facets = RichTextParser.buildFacets(from: detected, resolvedMentions: resolvedMentions)
            let via = appSettings.showVia ? appSettings.viaName : nil
            _ = try await postService.createPost(
                text: text,
                facets: facets.isEmpty ? nil : facets,
                replyTo: replyTarget,
                quotePost: quotePost,
                images: uploadedImages.isEmpty ? nil : uploadedImages,
                video: uploadedVideo,
                via: via
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isPosting = false
    }

    // Bluesky 画像アップロード制限
    // サーバー側の実際の制限は 976,562 bytes (976.56KB)
    // 安全マージンを確保して 950KB に設定（デスクトップ版 OGP_MAX_BYTES と同値）
    private static let imageMaxBytes = 950_000
    private static let imageMaxWidth: CGFloat = 2048

    private func loadPickedImages(items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        var results: [SelectedImage] = []
        for item in items.prefix(4) {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            guard let uiImage = UIImage(data: data) else { continue }
            // CGImage バッキングを確立して正規化
            let normalized: UIImage
            if let cg = uiImage.cgImage {
                normalized = UIImage(cgImage: cg, scale: uiImage.scale, orientation: uiImage.imageOrientation)
            } else {
                normalized = uiImage
            }
            results.append(SelectedImage(image: normalized))
        }
        await MainActor.run {
            selectedImages = results
        }
    }

    /// デスクトップ版 compressImageFile と同等のロジック。
    /// image.size はポイント単位なので、ピクセル単位（size × scale）で比較する。
    /// 最大幅 2048px に収まるようリサイズし、JPEG 品質を 0.85→0.3 と段階的に落として 950KB 以下にする。
    private func compressImage(_ image: UIImage) -> (Data, String)? {
        let maxBytes = Self.imageMaxBytes
        let maxWidthPx = Self.imageMaxWidth  // ピクセル単位

        // 実ピクセルサイズ
        let pixelWidth  = image.size.width  * image.scale
        let pixelHeight = image.size.height * image.scale

        // スケール計算（ピクセル幅が 2048px を超える場合のみ縮小）
        let scale = min(1.0, maxWidthPx / pixelWidth)
        let targetPixelSize = CGSize(
            width:  round(pixelWidth  * scale),
            height: round(pixelHeight * scale)
        )

        // リサイズ（UIGraphicsImageRenderer は scale=1 でピクセル等倍描画）
        let drawImage: UIImage
        if scale < 1.0 {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0  // 出力を実ピクセル等倍にする
            let renderer = UIGraphicsImageRenderer(size: targetPixelSize, format: format)
            drawImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: targetPixelSize))
            }
        } else {
            // リサイズ不要でも scale=1 の UIImage に正規化してから JPEG 変換
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0
            let renderer = UIGraphicsImageRenderer(
                size: CGSize(width: pixelWidth, height: pixelHeight),
                format: format
            )
            drawImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: CGSize(width: pixelWidth, height: pixelHeight)))
            }
        }

        // 品質を段階的に低下（0.85 → 0.3、0.1 ステップ）
        var quality: CGFloat = 0.85
        while quality >= 0.3 {
            if let data = drawImage.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return (data, "image/jpeg")
            }
            quality -= 0.1
        }
        // フォールバック: 最低品質 0.2
        if let data = drawImage.jpegData(compressionQuality: 0.2) {
            return (data, "image/jpeg")
        }
        return nil
    }

    private func loadPickedVideo(item: PhotosPickerItem) async {
        // loadTransferable(type: Data.self) で動画バイナリを直接取得する
        // URL.self は実機の Photos サンドボックスで動作しないため Data.self を使用
        // AVAssetExportSession は写真ピッカー閉時のバックグラウンド遷移で中断されるため使用しない
        // サーバー側トランスコード（video.bsky.app）に任せるため raw data をそのまま使う
        guard let rawData = try? await item.loadTransferable(type: Data.self) else { return }

        // supportedContentTypes から MIME タイプを判定
        let mimeType: String
        if item.supportedContentTypes.contains(where: { $0.identifier.contains("quicktime") || $0.identifier.hasSuffix(".mov") }) {
            mimeType = "video/quicktime"
        } else {
            mimeType = "video/mp4"
        }

        // 一時ファイルに書き出してサムネイル生成用 AVURLAsset として使用
        let ext = mimeType == "video/quicktime" ? "mov" : "mp4"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try? rawData.write(to: tempURL)

        // サムネイル生成（ベストエフォート）
        let asset = AVURLAsset(url: tempURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let thumbnail = try? await {
            let (cgImage, _) = try await generator.image(at: .zero)
            return UIImage(cgImage: cgImage)
        }()

        await MainActor.run {
            selectedVideo = SelectedVideo(url: tempURL, data: rawData, mimeType: mimeType, thumbnail: thumbnail)
        }
    }

    // MARK: - メンションオートコンプリート

    /// テキスト変更時に末尾の @query を検出してタイプアヘッド検索を起動
    private func updateMentionQuery(text: String) {
        // 最後の @ 以降のトークンを取得（空白が来たら終了）
        let query = extractMentionQuery(from: text)
        if query == mentionQuery { return }
        mentionQuery = query
        mentionSearchTask?.cancel()

        guard let q = query, !q.isEmpty else {
            mentionCandidates = []
            return
        }

        mentionSearchTask = Task {
            // 150ms デバウンス
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            if let result = try? await searchService.searchActorsTypeahead(query: q) {
                await MainActor.run {
                    mentionCandidates = result.actors
                }
            }
        }
    }

    /// テキスト末尾から `@query` を抽出（空白・改行があれば nil）
    private func extractMentionQuery(from text: String) -> String? {
        // 末尾から遡って @ を探す
        let chars = Array(text)
        var i = chars.count - 1
        while i >= 0 {
            let c = chars[i]
            if c == "@" {
                let query = String(chars[(i + 1)...])
                // query に空白・改行が含まれていたら無効
                if query.contains(" ") || query.contains("\n") { return nil }
                return query
            }
            // 空白・改行が現れたら @ は存在しない
            if c == " " || c == "\n" { return nil }
            i -= 1
        }
        return nil
    }

    /// 候補を選択してテキストを補完
    private func applyMention(_ actor: ProfileViewBasic) {
        guard let query = mentionQuery else { return }
        // @query を @handle + スペースに置換
        let suffix = "@\(query)"
        if text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count)) + "@\(actor.handle) "
        }
        // DID をキャッシュ
        resolvedMentions[actor.handle] = actor.did
        mentionCandidates = []
        mentionQuery = nil
    }

    private var mentionSuggestionList: some View {
        VStack(spacing: 0) {
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(mentionCandidates, id: \.did) { actor in
                        Button {
                            applyMention(actor)
                        } label: {
                            HStack(spacing: 10) {
                                AvatarView(url: actor.avatar, size: 32)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(actor.displayNameOrHandle)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text("@\(actor.handle)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 58)
                    }
                }
            }
            .frame(maxHeight: 220)
            .background(.regularMaterial)
        }
    }

    // MARK: - Subviews

    /// 返信先・引用元の共通プレビュー（上部に統一表示）
    private func referencePreview(post: PostView, label: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: post.author.avatar, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(post.author.displayNameOrHandle)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                }
                Text(post.record.text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.06))
    }

    private var characterCounter: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: min(1.0, Double(graphemeCount) / 300.0))
                    .stroke(
                        remaining < 0 ? Color.red : remaining < 20 ? Color.orange : Color.accentColor,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 20, height: 20)

            if remaining <= 20 {
                Text("\(remaining)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(remaining < 0 ? .red : .secondary)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: remaining)
    }

    private var imagePreviewRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(selectedImages.enumerated()), id: \.element.id) { index, selected in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: selected.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .onTapGesture {
                                altText = selected.alt
                                editingAltIndex = index
                            }

                        // 削除ボタン
                        Button {
                            selectedImages.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                        }
                        .padding(4)

                        // ALT バッジ（alt が設定されている場合）
                        if !selected.alt.isEmpty {
                            Text("ALT")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
                                .padding(4)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        }

                        // クロップボタン（右下）
                        Button {
                            croppingImageIndex = index
                        } label: {
                            Image(systemName: "crop")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(Color.black.opacity(0.6), in: Circle())
                        }
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                    .frame(width: 80, height: 80)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - ALT テキスト編集シート

    @ViewBuilder
    private var altEditSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "image.altPlaceholder"), text: $altText, axis: .vertical)
                        .lineLimit(4...8)
                } header: {
                    Text(String(localized: "image.altTitle"))
                } footer: {
                    Text(String(localized: "image.altHint"))
                }

                // Claude API が設定されている場合のみ表示
                if !appSettings.claudeApiKey.isEmpty {
                    Section {
                        Button {
                            Task { await generateAltForCurrentImage() }
                        } label: {
                            HStack {
                                Label(String(localized: "image.altGenerate"), systemImage: "sparkles")
                                Spacer()
                                if isGeneratingAlt {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            }
                        }
                        .disabled(isGeneratingAlt)
                    } footer: {
                        if let err = altGenerationError {
                            Text(err).foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "image.altTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "compose.cancel")) { editingAltIndex = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "compose.done")) {
                        if let idx = editingAltIndex, idx < selectedImages.count {
                            selectedImages[idx].alt = altText
                        }
                        editingAltIndex = nil
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func generateAltForCurrentImage() async {
        guard let idx = editingAltIndex, idx < selectedImages.count else { return }
        let image = selectedImages[idx].image
        let apiKey = appSettings.claudeApiKey
        guard !apiKey.isEmpty else { return }

        isGeneratingAlt = true
        altGenerationError = nil

        do {
            // 投稿言語設定から言語コードを取得（resolvedPostLangs の先頭を使用）
            let langCode = appSettings.resolvedPostLangs.first ?? "ja"
            let generated = try await ClaudeService.generateAltText(
                for: image,
                apiKey: apiKey,
                languageCode: langCode
            )
            altText = generated
        } catch {
            altGenerationError = error.localizedDescription
        }

        isGeneratingAlt = false
    }

    private func videoPreviewRow(video: SelectedVideo) -> some View {
        HStack(spacing: 12) {
            ZStack {
                if let thumb = video.thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 80, height: 80)
                }
                Image(systemName: "play.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "compose.video"))
                    .font(.subheadline.weight(.semibold))
                let mb = Double(video.data.count) / 1_048_576
                Text(String(format: "%.1f MB", mb))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // 削除ボタン
            Button {
                selectedVideo = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var bottomBar: some View {
        HStack(spacing: 16) {
            // フォトピッカー（最大4枚、動画選択済みの場合は無効）
            // .compatible で HEIC→JPEG 変換を保証
            PhotosPicker(
                selection: $photoPickerItems,
                maxSelectionCount: max(0, 4 - selectedImages.count),
                matching: .images,
                preferredItemEncoding: .compatible
            ) {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundStyle((selectedImages.count >= 4 || selectedVideo != nil) ? .tertiary : .secondary)
            }
            .disabled(selectedImages.count >= 4 || selectedVideo != nil)

            // 動画ピッカー（画像選択済みの場合は無効）
            PhotosPicker(
                selection: $videoPickerItem,
                matching: .videos
            ) {
                Image(systemName: "video")
                    .font(.system(size: 20))
                    .foregroundStyle((!selectedImages.isEmpty || selectedVideo != nil) ? .tertiary : .secondary)
            }
            .disabled(!selectedImages.isEmpty || selectedVideo != nil)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
