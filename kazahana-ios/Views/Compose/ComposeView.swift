// ComposeView.swift
// kazahana-ios
// 投稿作成画面（新規投稿・リプライ・引用・画像・動画添付対応）

import SwiftUI
import PhotosUI
import UIKit
import AVKit
import UniformTypeIdentifiers

struct SelectedImage: Identifiable {
    let id = UUID()
    var image: UIImage   // クロップ後の置き換えを可能にするため var
    var alt: String = ""
}

/// ウォーターマーク確認モーダルに渡すデータ。.sheet(item:) で状態を確実に渡すためのラッパー。
struct WatermarkConfirmData: Identifiable {
    let id = UUID()
    let images: [SelectedImage]
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
    @Environment(AuthViewModel.self) private var authVM

    /// アップロード進捗の段階表示
    enum UploadStage: Equatable {
        case compressingImages
        case uploadingImage(current: Int, total: Int)
        case uploadingVideo
        case processingVideo
        case posting
    }

    // テキストは View の @State で直接管理（@Observable ViewModel の TextEditor バインディング問題を回避）
    @State private var text: String = ""
    @FocusState private var isTextEditorFocused: Bool
    @State private var isPosting = false
    @State private var uploadStage: UploadStage? = nil
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

    // ウォーターマーク確認モーダル用データ（nil = 非表示）
    @State private var watermarkConfirmImages: WatermarkConfirmData? = nil

    // スレッドゲート / ポストゲート
    @State private var threadgateSetting: ThreadgateSetting = .everyone
    @State private var disableEmbedding: Bool = false
    @State private var showThreadgateSheet: Bool = false
    @State private var showPostgateSheet: Bool = false

    // カメラ
    @State private var showCamera: Bool = false
    @State private var cameraMediaType: CameraView.MediaType = .photo


    // 長文投稿サービス
    @State private var showLongFormSafari: Bool = false

    // 下書き
    @State private var showCancelDraftDialog: Bool = false
    @State private var showDraftList: Bool = false
    @State private var showDraftImageWarning: Bool = false

    // メンションオートコンプリート
    @State private var mentionCandidates: [ProfileViewBasic] = []
    @State private var mentionQuery: String? = nil   // nil = 非アクティブ
    @State private var mentionSearchTask: Task<Void, Never>? = nil
    // 解決済みメンション DID（handle → did のキャッシュ）
    @State private var resolvedMentions: [String: String] = [:]

    #if targetEnvironment(macCatalyst)
    @State private var isDragTarget = false
    #endif

    // リンクカードプレビュー
    @State private var detectedURL: URL? = nil          // テキスト中で検出した URL
    @State private var linkPreview: LinkPreview? = nil  // 取得済みプレビュー
    @State private var isLoadingLinkPreview: Bool = false
    @State private var linkPreviewTask: Task<Void, Never>? = nil

    private let postService: PostService
    private let searchService: SearchService
    private let linkPreviewService: LinkPreviewService
    private let replyToPost: PostView?
    private let replyTarget: ReplyTarget?
    private let quotePost: PostView?

    init(postService: PostService, searchService: SearchService? = nil, replyTo: PostView? = nil, quotedPost: PostView? = nil, initialText: String = "") {
        self.postService = postService
        self.searchService = searchService ?? SearchService(client: postService.atProtoClient)
        self.linkPreviewService = LinkPreviewService(client: postService.atProtoClient)
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
        self._text = State(initialValue: initialText)
    }

    private var graphemeCount: Int { text.count }
    private var remaining: Int { 300 - graphemeCount }
    private var canPost: Bool { (graphemeCount > 0 || !selectedImages.isEmpty || selectedVideo != nil) && remaining >= 0 && !isPosting }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // カスタムヘッダー（Catalyst のツールバーが黒背景になる問題の回避）
                composeHeader

                Divider()

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
                    textEditorView

                    // メンション候補リスト
                    if !mentionCandidates.isEmpty {
                        mentionSuggestionList
                    }
                }

                // リンクカードプレビュー（画像・動画なし かつ 引用なし の場合のみ表示）
                linkCardSection

                // リンクカード手動生成ボタン（手打ちURL検出時・Divider付き）
                if selectedImages.isEmpty && selectedVideo == nil && quotePost == nil,
                   detectedURL != nil, linkPreview == nil, !isLoadingLinkPreview {
                    Divider()
                }
                linkCardGenerateButton

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
            .navigationBarHidden(true)
            .task {
                // initialText に URL が含まれる場合（Share Extension / Edge共有経由）
                // リンクカードを自動フェッチ
                guard selectedImages.isEmpty, selectedVideo == nil, quotePost == nil else { return }
                if let url = LinkPreviewService.detectFirstURL(in: text) {
                    detectedURL = url
                    fetchLinkCard(url: url)
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
            // ウォーターマーク確認モーダル（.sheet(item:) で確実に画像を渡す）
            .sheet(item: $watermarkConfirmImages) { data in
                watermarkConfirmSheet(data: data)
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
            // カメラ撮影
            #if !targetEnvironment(macCatalyst)
            .fullScreenCover(isPresented: $showCamera) {
                CameraView(mediaType: cameraMediaType) { result in
                    switch result {
                    case .photo(let image):
                        if selectedImages.count < 10 {
                            selectedImages.append(SelectedImage(image: image))
                        }
                    case .video(let url):
                        Task { await loadCapturedVideo(url: url) }
                    }
                }
            }
            #endif
            .onChange(of: photoPickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task { await loadPickedImages(items: newItems) }
            }
            #if targetEnvironment(macCatalyst)
            .onReceive(NotificationCenter.default.publisher(for: CatalystMediaPicker.pickedNotification)) { notif in
                // 画像
                if let images = notif.userInfo?["images"] as? [UIImage] {
                    let remaining = 10 - selectedImages.count
                    for image in images.prefix(remaining) {
                        selectedImages.append(SelectedImage(image: image))
                    }
                }
                // 動画（画像未選択時のみ、1本まで）
                if let videoURL = notif.userInfo?["videoURL"] as? URL,
                   selectedImages.isEmpty, selectedVideo == nil {
                    Task { await loadVideoFromURL(videoURL) }
                }
            }
            #endif
            .onChange(of: videoPickerItem) { _, newItem in
                guard let newItem else { return }
                Task { await loadPickedVideo(item: newItem) }
            }
            .overlay {
                if isPosting {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    uploadProgressOverlay
                }
            }
            // 下書き保存ダイアログ（キャンセル時）
            .confirmationDialog(
                String(localized: "compose.draft.saveTitle"),
                isPresented: $showCancelDraftDialog,
                titleVisibility: .visible
            ) {
                Button(String(localized: "compose.draft.save")) {
                    if !selectedImages.isEmpty && appSettings.confirmDraftImageQuality {
                        showDraftImageWarning = true
                    } else {
                        saveDraft()
                        dismiss()
                    }
                }
                Button(String(localized: "compose.draft.discard"), role: .destructive) {
                    dismiss()
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            }
            // 下書き保存時の画像品質警告
            .alert(String(localized: "draft.imageWarningTitle"), isPresented: $showDraftImageWarning) {
                Button(String(localized: "draft.saveAnyway")) {
                    saveDraft()
                    dismiss()
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "draft.imageWarningMessage"))
            }
            // 下書き一覧シート
            .sheet(isPresented: $showDraftList) {
                DraftListView { draft in
                    restoreDraft(draft)
                }
            }
            // 長文投稿サービス（SFSafariViewController）
            .sheet(isPresented: $showLongFormSafari) {
                if let url = URL(string: appSettings.longFormServiceUrl) {
                    SafariView(url: url)
                        .ignoresSafeArea()
                }
            }
            // macOS: Option+Return で投稿送信（メニューバー UIKeyCommand のフォールバック）
            .onReceive(NotificationCenter.default.publisher(for: .composeSubmitPost)) { _ in
                if canPost { Task { await submitPost() } }
            }
        }
    }

    // MARK: - TextEditor（型推論タイムアウト回避のため分離）

    @ViewBuilder
    private var textEditorView: some View {
        #if targetEnvironment(macCatalyst)
        CatalystTextEditor(text: $text, onOptionReturn: {
            if canPost { Task { await submitPost() } }
        }, onPasteImages: { images in
            let remaining = 10 - selectedImages.count
            guard remaining > 0 else { return }
            for image in images.prefix(remaining) {
                selectedImages.append(SelectedImage(image: image))
            }
        })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
        // Finder からのドラッグ＆ドロップ（テキストエリアのみに限定してボタン干渉を回避）
        // loadObject(ofClass: UIImage.self) は Finder ドロップでは機能しないため
        // loadFileRepresentation を使ってファイルURLから UIImage を生成する
        .onDrop(of: [.image, .movie], isTargeted: $isDragTarget) { providers in
            let group = DispatchGroup()
            var images: [UIImage] = []
            var videoURL: URL? = nil

            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    group.enter()
                    provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                        defer { group.leave() }
                        guard let url, videoURL == nil else { return }
                        let dest = FileManager.default.temporaryDirectory
                            .appendingPathComponent(url.lastPathComponent)
                        try? FileManager.default.copyItem(at: url, to: dest)
                        videoURL = dest
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    group.enter()
                    provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                        defer { group.leave() }
                        guard let url else { return }
                        let dest = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString + "." + url.pathExtension)
                        try? FileManager.default.copyItem(at: url, to: dest)
                        if let data = try? Data(contentsOf: dest),
                           let image = UIImage(data: data) {
                            images.append(image)
                        }
                    }
                }
            }

            group.notify(queue: .main) {
                var userInfo: [String: Any] = [:]
                if !images.isEmpty { userInfo["images"] = images }
                if let videoURL { userInfo["videoURL"] = videoURL }
                guard !userInfo.isEmpty else { return }
                NotificationCenter.default.post(
                    name: CatalystMediaPicker.pickedNotification,
                    object: nil,
                    userInfo: userInfo
                )
            }
            return true
        }
        .overlay {
            if isDragTarget {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .background(Color.accentColor.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // CatalystTextEditor は自動的にフォーカスを取る
            }
        }
        .onChange(of: text) { oldValue, newValue in
            updateMentionQuery(text: newValue)
            updateLinkPreview(oldText: oldValue, newText: newValue)
        }
        #else
        TextEditor(text: $text)
            .font(appSettings.fontSize.bodyFont)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 12)
            .scrollContentBackground(.hidden)
            .focused($isTextEditorFocused)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isTextEditorFocused = true
                }
            }
            .onChange(of: text) { oldValue, newValue in
                updateMentionQuery(text: newValue)
                updateLinkPreview(oldText: oldValue, newText: newValue)
            }
        #endif
    }

    // MARK: - カスタムヘッダー（Catalyst ツールバー黒背景回避）

    private var composeHeader: some View {
        HStack {
            Button(String(localized: "compose.cancel")) {
                let hasContent = !text.isEmpty || !selectedImages.isEmpty || selectedVideo != nil
                if hasContent && replyTarget == nil && quotePost == nil {
                    showCancelDraftDialog = true
                } else {
                    dismiss()
                }
            }

            Spacer()

            Text(composeTitle)
                .font(.headline)

            Spacer()

            // WMなしで投稿（ウォーターマーク有効 && 画像あり時のみ表示）
            if appSettings.watermarkSettings.enabled && !selectedImages.isEmpty {
                Button(String(localized: "watermark.postWithout")) {
                    Task { await submitPost(skipWatermark: true) }
                }
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .disabled(!canPost)
            }

            Button(String(localized: "compose.post")) {
                Task { await submitPost() }
            }
            .fontWeight(.bold)
            .disabled(!canPost)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
    }

    private var composeTitle: String {
        if replyToPost != nil {
            return String(localized: "compose.reply")
        } else if quotePost != nil {
            return String(localized: "compose.quotePost")
        } else {
            return String(localized: "compose.newPost")
        }
    }


    // MARK: - Actions

    private func submitPost(skipWatermark: Bool = false) async {
        guard canPost else { return }

        let wm = appSettings.watermarkSettings
        let handle = authVM.client.currentSession?.handle ?? ""

        // ウォーターマーク有効 && 画像あり && スキップしない → 合成してから確認 or 直接投稿
        if wm.enabled && !selectedImages.isEmpty && !skipWatermark {
            // メインアクターで合成（UIGraphicsImageRenderer はメインスレッド必須）
            let watermarked = await MainActor.run {
                selectedImages.map { selected in
                    SelectedImage(
                        image: WatermarkService.apply(to: selected.image, settings: wm, handle: handle),
                        alt: selected.alt
                    )
                }
            }
            if wm.confirmBeforePost {
                // .sheet(item:) に渡すことでシート表示時に確実に画像が存在することを保証
                watermarkConfirmImages = WatermarkConfirmData(images: watermarked)
                return
            }
            // 確認なしで直接投稿
            await uploadAndPost(images: watermarked)
            return
        }

        // ウォーターマークなしで投稿
        await uploadAndPost(images: selectedImages)
    }

    private func uploadAndPost(images: [SelectedImage]) async {
        isPosting = true
        uploadStage = nil
        errorMessage = nil

        do {
            // 画像をアップロード（2 MB 超の場合は自動圧縮・リサイズ。古い PDS は 413 時に 1 MB で再試行）
            var uploadedImages: [(blob: BlobRef, alt: String, aspectRatio: AspectRatioCreate?)] = []
            let imageTotal = images.count
            if imageTotal > 0 {
                uploadStage = .compressingImages
            }
            for (index, selected) in images.enumerated() {
                let img = selected.image
                let pixW = Int(img.size.width * img.scale)
                let pixH = Int(img.size.height * img.scale)
                let aspectRatio = (pixW > 0 && pixH > 0) ? AspectRatioCreate(width: pixW, height: pixH) : nil
                guard let (imageData, mimeType) = compressImage(img) else { continue }
                uploadStage = .uploadingImage(current: index + 1, total: imageTotal)
                let blob = try await uploadImageWithFallback(image: img, data: imageData, mimeType: mimeType)
                uploadedImages.append((blob: blob, alt: selected.alt, aspectRatio: aspectRatio))
            }

            // 動画をアップロード（送信 → 変換処理の2段階で進捗表示）
            var uploadedVideo: (blob: BlobRef, alt: String?, aspectRatio: AspectRatioCreate?)? = nil
            if let video = selectedVideo {
                uploadStage = .uploadingVideo
                let (jobStatus, serviceToken) = try await postService.startVideoUpload(data: video.data, mimeType: video.mimeType)
                uploadStage = .processingVideo
                let blob = try await postService.waitForVideoProcessing(jobId: jobStatus.jobId, serviceToken: serviceToken)
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

            // リンクカード: サムネイルをアップロードして BlobRef をセット
            var finalLinkPreview = (uploadedImages.isEmpty && uploadedVideo == nil && quotePost == nil)
                ? linkPreview
                : nil
            if var preview = finalLinkPreview, let thumbImage = preview.thumbImage {
                preview.thumbBlob = try? await linkPreviewService.uploadThumbnail(image: thumbImage)
                finalLinkPreview = preview
            }

            uploadStage = .posting
            let detected = RichTextParser.detectFacets(in: text)
            let facets = RichTextParser.buildFacets(from: detected, resolvedMentions: resolvedMentions)
            let via = appSettings.showVia ? appSettings.viaName : nil
            let response = try await postService.createPost(
                text: text,
                facets: facets.isEmpty ? nil : facets,
                replyTo: replyTarget,
                quotePost: quotePost,
                images: uploadedImages.isEmpty ? nil : uploadedImages,
                video: uploadedVideo,
                linkCard: finalLinkPreview,
                via: via
            )
            // スレッドゲート（返信制限）—— 返信投稿には設定不可
            if replyTarget == nil && threadgateSetting != .everyone {
                try? await postService.createThreadgate(postURI: response.uri, setting: threadgateSetting)
            }
            // ポストゲート（引用制限）
            if disableEmbedding {
                try? await postService.createPostgate(postURI: response.uri, disableEmbedding: true)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isPosting = false
        uploadStage = nil
    }

    // MARK: - アップロード進捗オーバーレイ

    @ViewBuilder
    private var uploadProgressOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.3)
                .tint(.white)

            if let stage = uploadStage {
                Text(uploadStageText(stage))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
        .background(.ultraThinMaterial.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
        .animation(.easeInOut(duration: 0.2), value: uploadStage)
    }

    private func uploadStageText(_ stage: UploadStage) -> String {
        switch stage {
        case .compressingImages:
            return String(localized: "compose.upload.compressingImages")
        case .uploadingImage(let current, let total):
            if total == 1 {
                return String(localized: "compose.upload.uploadingImage")
            }
            return String(localized: "compose.upload.uploadingImageN \(current) \(total)")
        case .uploadingVideo:
            return String(localized: "compose.upload.uploadingVideo")
        case .processingVideo:
            return String(localized: "compose.upload.processingVideo")
        case .posting:
            return String(localized: "compose.upload.posting")
        }
    }

    // MARK: - 下書き

    private func saveDraft() {
        let threadgateIdx = ThreadgateSetting.allCases.firstIndex(of: threadgateSetting) ?? 0
        let imageItems: [(image: UIImage, alt: String)] = selectedImages.map { ($0.image, $0.alt) }
        let videoItem: (data: Data, mimeType: String, alt: String)? = selectedVideo.map {
            ($0.data, $0.mimeType, $0.alt)
        }
        DraftService.shared.save(
            text: text,
            images: imageItems,
            video: videoItem,
            threadgateIndex: threadgateIdx,
            disableEmbedding: disableEmbedding
        )
    }

    private func restoreDraft(_ draft: PostDraft) {
        // テキスト
        text = draft.text

        // スレッドゲート設定
        let cases = ThreadgateSetting.allCases
        if draft.threadgateIndex < cases.count {
            threadgateSetting = cases[draft.threadgateIndex]
        }
        disableEmbedding = draft.disableEmbedding

        // 画像を復元
        selectedImages = draft.images.compactMap { meta in
            guard let data = DraftService.shared.imageData(for: meta),
                  let uiImage = UIImage(data: data) else { return nil }
            return SelectedImage(image: uiImage, alt: meta.alt)
        }

        // 動画を復元
        if let videoMeta = draft.video,
           let data = DraftService.shared.videoData(for: videoMeta) {
            selectedVideo = SelectedVideo(
                url: URL(fileURLWithPath: videoMeta.filename),
                data: data,
                mimeType: videoMeta.mimeType,
                thumbnail: nil,
                alt: videoMeta.alt
            )
        } else {
            selectedVideo = nil
        }

        // 復元後に下書きを削除
        DraftService.shared.delete(id: draft.id)
    }

    // Bluesky 画像アップロード制限（公式仕様: 2 MB）
    /// 通常アップロード上限
    private static let imageMaxBytes = 2_000_000
    /// 古い PDS が 413 を返した場合のフォールバック上限
    private static let imageMaxBytesFallback = 1_000_000

    private func loadPickedImages(items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        var results: [SelectedImage] = []
        for item in items.prefix(10) {
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

    /// 公式クライアント互換の圧縮アルゴリズム。
    /// 最大辺 4000px からスタートし ×0.8 で段階的に縮小（最大 5 段）、それでも超える場合は品質を下げる。
    /// - Parameters:
    ///   - image: 圧縮元画像
    ///   - maxBytes: バイト上限（デフォルト 1.9 MB）
    private func compressImage(_ image: UIImage, maxBytes: Int = Self.imageMaxBytes) -> (Data, String)? {
        let pixelWidth  = image.size.width  * image.scale
        let pixelHeight = image.size.height * image.scale
        let currentMax  = max(pixelWidth, pixelHeight)

        // 4000 → 3200 → 2560 → 2048 → 1638 の順でリサイズを試みる
        var maxDimension: CGFloat = 4000
        while maxDimension >= 1000 {
            let s = min(1.0, maxDimension / currentMax)
            let targetSize = CGSize(width: round(pixelWidth * s), height: round(pixelHeight * s))
            let format = UIGraphicsImageRendererFormat(); format.scale = 1.0
            let drawn = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            if let data = drawn.jpegData(compressionQuality: 0.85), data.count <= maxBytes {
                return (data, "image/jpeg")
            }
            maxDimension = (maxDimension * 0.8).rounded(.down)
        }

        // 解像度を最小（1000px）に固定して品質を段階的に下げるフォールバック
        let fs = min(1.0, 1000 / currentMax)
        let fallbackSize = CGSize(width: round(pixelWidth * fs), height: round(pixelHeight * fs))
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1.0
        let fallback = UIGraphicsImageRenderer(size: fallbackSize, format: fmt).image { _ in
            image.draw(in: CGRect(origin: .zero, size: fallbackSize))
        }
        var quality: CGFloat = 0.7
        while quality >= 0.2 {
            if let data = fallback.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return (data, "image/jpeg")
            }
            quality -= 0.1
        }
        return fallback.jpegData(compressionQuality: 0.1).map { ($0, "image/jpeg") }
    }

    /// 画像をアップロードし、PDS が 413 を返した場合は 1 MB 以下に再圧縮して再試行する
    private func uploadImageWithFallback(image: UIImage, data: Data, mimeType: String) async throws -> BlobRef {
        do {
            return try await postService.uploadImage(data: data, mimeType: mimeType)
        } catch ATProtoError.httpError(let code) where code == 413 || code == 400 {
            guard let (fallbackData, fallbackMime) = compressImage(image, maxBytes: Self.imageMaxBytesFallback) else {
                throw ATProtoError.httpError(statusCode: code)
            }
            return try await postService.uploadImage(data: fallbackData, mimeType: fallbackMime)
        }
    }

    /// 動画アップロード上限（クライアントガード、サーバーが受容する最大サイズ）
    private static let videoMaxBytes = 300 * 1024 * 1024  // 300 MB

    private func loadPickedVideo(item: PhotosPickerItem) async {
        // loadTransferable(type: Data.self) で動画バイナリを直接取得する
        // URL.self は実機の Photos サンドボックスで動作しないため Data.self を使用
        // AVAssetExportSession は写真ピッカー閉時のバックグラウンド遷移で中断されるため使用しない
        // サーバー側トランスコード（video.bsky.app）に任せるため raw data をそのまま使う
        guard let rawData = try? await item.loadTransferable(type: Data.self) else { return }

        // クライアント側サイズガード（300 MB）
        if rawData.count > Self.videoMaxBytes {
            let mb = Double(rawData.count) / 1_048_576
            await MainActor.run {
                errorMessage = String(localized: "compose.video.tooLarge \(String(format: "%.0f", mb))")
            }
            return
        }

        // サーバー側アップロード制限を確認（ベストエフォート）
        if let limits = try? await postService.getVideoUploadLimits() {
            if !limits.canUpload {
                await MainActor.run {
                    errorMessage = limits.message ?? String(localized: "compose.video.uploadDisabled")
                }
                return
            }
            if let remainingBytes = limits.remainingDailyBytes, rawData.count > remainingBytes {
                let remainingMB = Double(remainingBytes) / 1_048_576
                await MainActor.run {
                    errorMessage = String(localized: "compose.video.dailyLimitExceeded \(String(format: "%.0f", remainingMB))")
                }
                return
            }
        }

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

    // MARK: - カメラ撮影動画の読み込み

    private func loadCapturedVideo(url: URL) async {
        guard let data = try? Data(contentsOf: url) else { return }
        let ext = url.pathExtension.lowercased()
        let mimeType = ext == "mov" ? "video/quicktime" : "video/mp4"

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let thumbnail = try? await {
            let (cgImage, _) = try await generator.image(at: .zero)
            return UIImage(cgImage: cgImage)
        }()

        await MainActor.run {
            selectedVideo = SelectedVideo(url: url, data: data, mimeType: mimeType, thumbnail: thumbnail)
        }
    }

    /// Finder で選択された動画ファイルを SelectedVideo に変換（macOS Catalyst 用）
    private func loadVideoFromURL(_ url: URL) async {
        guard let data = try? Data(contentsOf: url) else { return }
        let ext = url.pathExtension.lowercased()
        let mimeType = ext == "mov" ? "video/quicktime" : "video/mp4"

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let thumbnail = try? await {
            let (cgImage, _) = try await generator.image(at: .zero)
            return UIImage(cgImage: cgImage)
        }()

        await MainActor.run {
            selectedVideo = SelectedVideo(url: url, data: data, mimeType: mimeType, thumbnail: thumbnail)
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

    // MARK: - リンクカードプレビュー

    @ViewBuilder
    private var linkCardSection: some View {
        if selectedImages.isEmpty && selectedVideo == nil && quotePost == nil {
            if isLoadingLinkPreview {
                Divider()
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text(String(localized: "compose.linkCard.loading"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            } else if let preview = linkPreview {
                Divider()
                linkCardPreviewRow(preview)
            }
        }
    }

    /// 手打ちURL検出時に表示するリンクカード生成ボタン（インライン）
    @ViewBuilder
    var linkCardGenerateButton: some View {
        if selectedImages.isEmpty && selectedVideo == nil && quotePost == nil,
           detectedURL != nil, linkPreview == nil, !isLoadingLinkPreview {
            Button {
                if let url = detectedURL {
                    fetchLinkCard(url: url)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 13))
                    Text(String(localized: "compose.generateLinkCard"))
                        .font(.subheadline)
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
        }
    }

    /// テキスト変更時に URL を検出し、ペースト時のみ自動フェッチする
    private func updateLinkPreview(oldText: String, newText: String) {
        // 画像・動画・引用があるときはリンクカード不要
        guard selectedImages.isEmpty, selectedVideo == nil, quotePost == nil else { return }

        let url = LinkPreviewService.detectFirstURL(in: newText)

        // URL が変わった場合のみ処理（同じ URL のままなら何もしない）
        if url == detectedURL { return }
        detectedURL = url

        // URL がなくなったらプレビューをリセット
        guard let url else {
            linkPreview = nil
            linkPreviewTask?.cancel()
            isLoadingLinkPreview = false
            return
        }

        // ペースト検出：差分文字数が URL 文字列長以上 → ペーストと判断して自動フェッチ
        // 手打ちの場合は 1 文字ずつしか増えないので URL 全体が一度に入ることはない
        let addedLength = newText.count - oldText.count
        let isPaste = addedLength >= url.absoluteString.count

        if isPaste {
            fetchLinkCard(url: url)
        }
        // 手打ちの場合は detectedURL のみ更新してボタン表示に任せる
    }

    /// 指定 URL のリンクカードをフェッチして linkPreview にセットする
    private func fetchLinkCard(url: URL) {
        linkPreviewTask?.cancel()
        isLoadingLinkPreview = true
        let task = Task {
            do {
                let preview = try await linkPreviewService.fetchPreview(url: url)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isLoadingLinkPreview = false
                    linkPreview = preview
                }
            } catch {
                await MainActor.run { isLoadingLinkPreview = false }
            }
        }
        linkPreviewTask = task
    }

    /// プレビューカード UI
    @ViewBuilder
    private func linkCardPreviewRow(_ preview: LinkPreview) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Standard Site 拡張プレビューがあれば LinkCardView を使用
            if let extView = preview.externalView, extView.source != nil {
                LinkCardView(external: extView, hideSubscribe: true)
            } else {
                // 通常の OGP プレビュー
                HStack(alignment: .top, spacing: 10) {
                    if let thumb = preview.thumbImage {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: 56, height: 56)
                            .overlay {
                                Image(systemName: "link")
                                    .foregroundStyle(.secondary)
                            }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(preview.url.host ?? preview.url.absoluteString)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(preview.title.isEmpty ? preview.url.absoluteString : preview.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                        if !preview.description.isEmpty {
                            Text(preview.description)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }

            Spacer()

            // 削除ボタン
            Button {
                linkPreview = nil
                detectedURL = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
                            .frame(width: 110, height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .onTapGesture {
                                altText = selected.alt
                                editingAltIndex = index
                            }

                        // 削除ボタン
                        Button {
                            selectedImages.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
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
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(Color.black.opacity(0.6), in: Circle())
                        }
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                    .frame(width: 110, height: 110)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - ウォーターマーク確認モーダル

    @ViewBuilder
    private func watermarkConfirmSheet(data: WatermarkConfirmData) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text(String(localized: "watermark.confirmMessage"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    // 画像プレビュー（1枚: 単独表示 / 複数: 2列グリッド）
                    if data.images.count == 1, let first = data.images.first {
                        Image(uiImage: first.image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal)
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 8
                        ) {
                            ForEach(data.images) { selected in
                                Image(uiImage: selected.image)
                                    .resizable()
                                    .scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.horizontal)
                    }

                    // ボタン群
                    VStack(spacing: 10) {
                        Button {
                            let toPost = data.images
                            watermarkConfirmImages = nil
                            Task { await uploadAndPost(images: toPost) }
                        } label: {
                            Text(String(localized: "compose.post"))
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            watermarkConfirmImages = nil
                            Task { await uploadAndPost(images: selectedImages) }
                        } label: {
                            Text(String(localized: "watermark.postWithout"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button(String(localized: "common.cancel"), role: .cancel) {
                            watermarkConfirmImages = nil
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                .padding(.top, 16)
            }
            .navigationTitle(String(localized: "watermark.confirmTitle"))
            .navigationBarTitleDisplayMode(.inline)
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
            #if targetEnvironment(macCatalyst)
            // macOS: Finder ダイアログで写真/ビデオを統合選択
            // 写真選択済み → 写真のみ追加可、ビデオ選択済み → 無効
            Button {
                if selectedImages.isEmpty && selectedVideo == nil {
                    // 未選択: 画像＋動画の両方を許可
                    CatalystMediaPicker.present(contentTypes: [.image, .movie])
                } else {
                    // 画像選択済み: 画像のみ追加可
                    CatalystMediaPicker.present(contentTypes: [.image])
                }
            } label: {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 20))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
                    .foregroundStyle((selectedImages.count >= 10 || selectedVideo != nil) ? .tertiary : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(selectedImages.count >= 10 || selectedVideo != nil)
            #else
            // iOS: フォトピッカー（最大10枚、動画選択済みの場合は無効）
            PhotosPicker(
                selection: $photoPickerItems,
                maxSelectionCount: max(0, 10 - selectedImages.count),
                matching: .images,
                preferredItemEncoding: .compatible
            ) {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
                    .foregroundStyle((selectedImages.count >= 10 || selectedVideo != nil) ? .tertiary : .secondary)
            }
            .disabled(selectedImages.count >= 10 || selectedVideo != nil)

            // 動画ピッカー（画像選択済みの場合は無効）
            PhotosPicker(
                selection: $videoPickerItem,
                matching: .videos
            ) {
                Image(systemName: "video")
                    .font(.system(size: 20))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
                    .foregroundStyle((!selectedImages.isEmpty || selectedVideo != nil) ? .tertiary : .secondary)
            }
            .disabled(!selectedImages.isEmpty || selectedVideo != nil)
            #endif

            // 撮影ボタン（iOS のみ、Catalyst はカメラ非対応）
            #if !targetEnvironment(macCatalyst)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Menu {
                    Button {
                        cameraMediaType = .photo
                        showCamera = true
                    } label: {
                        Label(String(localized: "compose.camera.photo"), systemImage: "camera")
                    }
                    .disabled(selectedImages.count >= 10 || selectedVideo != nil)

                    Button {
                        cameraMediaType = .video
                        showCamera = true
                    } label: {
                        Label(String(localized: "compose.camera.video"), systemImage: "video")
                    }
                    .disabled(!selectedImages.isEmpty || selectedVideo != nil)
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 20))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                        .foregroundStyle(
                            (selectedImages.count >= 10 && selectedVideo != nil) ? .tertiary : .secondary
                        )
                }
            }
            #endif

            // 長文を書く（設定済みの場合のみ表示）
            if let longFormURL = URL(string: appSettings.longFormServiceUrl),
               longFormURL.scheme == "https" {
                Button {
                    showLongFormSafari = true
                } label: {
                    Image(systemName: "doc.text")
                        .font(.system(size: 20))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(String(localized: "compose.longform.button"))
            }

            // スレッドゲート（返信制限）—— 返信投稿では非表示
            if replyTarget == nil {
                // スレッドゲートボタン
                Button {
                    showThreadgateSheet = true
                } label: {
                    Image(systemName: threadgateSetting == .everyone
                          ? "bubble.left.and.bubble.right"
                          : "bubble.left.and.exclamationmark.bubble.right")
                        .font(.system(size: 20))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                        .foregroundStyle(threadgateSetting == .everyone ? Color.secondary : Color.accentColor)
                }
                .confirmationDialog(
                    String(localized: "compose.threadgate.title"),
                    isPresented: $showThreadgateSheet,
                    titleVisibility: .visible
                ) {
                    ForEach(ThreadgateSetting.allCases, id: \.self) { setting in
                        // 現在選択中の項目には先頭に ✓ を付けて判別できるようにする
                        Button {
                            threadgateSetting = setting
                        } label: {
                            Text(threadgateSetting == setting
                                 ? "✓ \(setting.displayName)"
                                 : setting.displayName)
                        }
                    }
                    Button(String(localized: "common.cancel"), role: .cancel) {}
                }

                // ポストゲートボタン（引用制限）
                Button {
                    showPostgateSheet = true
                } label: {
                    Image(systemName: disableEmbedding ? "quote.bubble.fill" : "quote.bubble")
                        .font(.system(size: 20))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                        .foregroundStyle(disableEmbedding ? Color.accentColor : Color.secondary)
                }
                .confirmationDialog(
                    String(localized: "compose.postgate.title"),
                    isPresented: $showPostgateSheet,
                    titleVisibility: .visible
                ) {
                    Button {
                        disableEmbedding = false
                    } label: {
                        Text(!disableEmbedding
                             ? "✓ \(String(localized: "compose.postgate.allow"))"
                             : String(localized: "compose.postgate.allow"))
                    }
                    Button {
                        disableEmbedding = true
                    } label: {
                        Text(disableEmbedding
                             ? "✓ \(String(localized: "compose.postgate.disable"))"
                             : String(localized: "compose.postgate.disable"))
                    }
                    Button(String(localized: "common.cancel"), role: .cancel) {}
                }
            }

            Spacer()

            // 下書きボタン（新規投稿時のみ表示）
            if replyTarget == nil && quotePost == nil {
                Button {
                    showDraftList = true
                } label: {
                    Text(String(localized: "compose.draft.button"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Catalyst 用ファイルピッカー（UIKit 直接表示でクラッシュ回避）

#if targetEnvironment(macCatalyst)
/// macOS Catalyst: Finder のメディア選択ダイアログを ComposeSheet の上に表示する。
/// 画像・動画の選択結果を Notification で SwiftUI 側に通知。
enum CatalystMediaPicker {
    static let pickedNotification = Notification.Name("CatalystMediaPickerPicked")
    private static var activeDelegate: PickerDelegate?

    static func present(contentTypes: [UTType]) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let keyWindow = scene.keyWindow,
              let root = keyWindow.rootViewController
        else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.allowsMultipleSelection = true
        let delegate = PickerDelegate()
        picker.delegate = delegate
        activeDelegate = delegate
        top.present(picker, animated: true)
    }

    private class PickerDelegate: NSObject, UIDocumentPickerDelegate {
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            CatalystMediaPicker.activeDelegate = nil
            var images: [UIImage] = []
            var videoURL: URL?
            for url in urls {
                let uti = UTType(filenameExtension: url.pathExtension) ?? .data
                if uti.conforms(to: .movie) || uti.conforms(to: .video) {
                    // 動画は1つだけ
                    if videoURL == nil { videoURL = url }
                } else if uti.conforms(to: .image) {
                    if let data = try? Data(contentsOf: url),
                       let image = UIImage(data: data) {
                        images.append(image)
                    }
                }
            }
            var userInfo: [String: Any] = [:]
            if !images.isEmpty { userInfo["images"] = images }
            if let videoURL { userInfo["videoURL"] = videoURL }
            guard !userInfo.isEmpty else { return }
            NotificationCenter.default.post(
                name: CatalystMediaPicker.pickedNotification,
                object: nil,
                userInfo: userInfo
            )
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            CatalystMediaPicker.activeDelegate = nil
        }
    }
}
#endif

// MARK: - Catalyst 用 UITextView ラッパー（Option+Return で投稿送信）

#if targetEnvironment(macCatalyst)
/// UITextView をサブクラス化し、Option+Return を keyCommands で奪うことで
/// テキスト入力システムより先にイベントを捕捉する。
/// SwiftUI の TextEditor / .onKeyPress では UITextView が改行として消費した後にしか
/// イベントが届かないため、この方式が必要。
struct CatalystTextEditor: UIViewRepresentable {
    @Binding var text: String
    var onOptionReturn: () -> Void
    var onPasteImages: (([UIImage]) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> SubmitTextView {
        let tv = SubmitTextView()
        tv.delegate = context.coordinator
        tv.onOptionReturn = onOptionReturn
        tv.onPasteImages = { images in
            self.onPasteImages?(images)
        }
        tv.font = AppSettings.shared.fontSize.uiFont
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        tv.text = text
        // 自動フォーカス
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            tv.becomeFirstResponder()
        }
        return tv
    }

    func updateUIView(_ uiView: SubmitTextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.font = AppSettings.shared.fontSize.uiFont
        uiView.onPasteImages = { images in
            self.onPasteImages?(images)
        }
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: CatalystTextEditor

        init(_ parent: CatalystTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
    }

    /// Option+Return を keyCommands でオーバーライドし、
    /// 画像ペーストをインターセプトする UITextView サブクラス
    class SubmitTextView: UITextView {
        var onOptionReturn: (() -> Void)?
        var onPasteImages: (([UIImage]) -> Void)?

        private lazy var optionReturnCommand: UIKeyCommand = {
            UIKeyCommand(
                input: "\r",
                modifierFlags: .alternate,
                action: #selector(handleOptionReturn)
            )
        }()

        override var keyCommands: [UIKeyCommand]? {
            return [optionReturnCommand] + (super.keyCommands ?? [])
        }

        @objc private func handleOptionReturn() {
            onOptionReturn?()
        }

        override func paste(_ sender: Any?) {
            let pb = UIPasteboard.general
            // クリップボードに画像がある場合はインターセプト
            if pb.hasImages, let images = pb.images, !images.isEmpty {
                onPasteImages?(images)
                return
            }
            // テキスト等はデフォルトのペースト処理に委譲
            super.paste(sender)
        }

        override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
            if action == #selector(paste(_:)) {
                // 画像がクリップボードにある場合もペーストを有効にする
                if UIPasteboard.general.hasImages { return true }
            }
            return super.canPerformAction(action, withSender: sender)
        }
    }
}
#endif

// MARK: - カメラ撮影ビュー（UIImagePickerController ラッパー）

struct CameraView: UIViewControllerRepresentable {
    enum MediaType {
        case photo
        case video
    }

    enum CaptureResult {
        case photo(UIImage)
        case video(URL)
    }

    let mediaType: MediaType
    let onCapture: (CaptureResult) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator

        switch mediaType {
        case .photo:
            picker.mediaTypes = ["public.image"]
            picker.cameraCaptureMode = .photo
        case .video:
            picker.mediaTypes = ["public.movie"]
            picker.cameraCaptureMode = .video
            picker.videoQuality = .typeHigh
        }

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(.photo(image))
            } else if let videoURL = info[.mediaURL] as? URL {
                parent.onCapture(.video(videoURL))
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
