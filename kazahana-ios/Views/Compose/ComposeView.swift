// ComposeView.swift
// kazahana-ios
// 投稿作成画面（新規投稿・リプライ・引用・画像添付対応）

import SwiftUI
import PhotosUI
import UIKit

struct SelectedImage: Identifiable {
    let id = UUID()
    let image: UIImage
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
    private var canPost: Bool { (graphemeCount > 0 || !selectedImages.isEmpty) && remaining >= 0 && !isPosting }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // リプライ先プレビュー
                if let replyTo = replyToPost {
                    replyPreview(post: replyTo)
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

                // 引用投稿プレビュー
                if let quoted = quotePost {
                    Divider()
                    quotePreview(post: quoted)
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
            .navigationTitle(replyToPost != nil ? "返信" : quotePost != nil ? "引用投稿" : "新規投稿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("投稿") {
                        Task { await submitPost() }
                    }
                    .fontWeight(.bold)
                    .disabled(!canPost)
                }
            }
            .alert("エラー", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            // Alt テキスト入力ダイアログ
            .alert("Alt テキスト", isPresented: Binding(
                get: { editingAltIndex != nil },
                set: { if !$0 { editingAltIndex = nil } }
            )) {
                TextField("画像の説明（任意）", text: $altText)
                Button("完了") {
                    if let idx = editingAltIndex {
                        selectedImages[idx].alt = altText
                    }
                    editingAltIndex = nil
                }
                Button("キャンセル", role: .cancel) { editingAltIndex = nil }
            } message: {
                Text("画像の内容を説明するテキストを入力してください")
            }
            .onChange(of: photoPickerItems) { _, newItems in
                Task { await loadPickedImages(items: newItems) }
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
            // 画像をアップロード
            var uploadedImages: [(blob: BlobRef, alt: String)] = []
            for selected in selectedImages {
                if let data = selected.image.jpegData(compressionQuality: 0.9) {
                    let blob = try await postService.uploadImage(data: data, mimeType: "image/jpeg")
                    uploadedImages.append((blob: blob, alt: selected.alt))
                }
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
                via: via
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isPosting = false
    }

    private func loadPickedImages(items: [PhotosPickerItem]) async {
        var results: [SelectedImage] = []
        for item in items.prefix(4) {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                results.append(SelectedImage(image: uiImage))
            }
        }
        await MainActor.run {
            selectedImages = results
            photoPickerItems = []
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

    private func quotePreview(post: PostView) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: post.author.avatar, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(post.author.displayNameOrHandle)
                    .font(.caption.weight(.semibold))
                Text(post.record.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func replyPreview(post: PostView) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: post.author.avatar, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(post.author.displayNameOrHandle)
                    .font(.footnote.weight(.semibold))
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
                    }
                    .frame(width: 80, height: 80)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var bottomBar: some View {
        HStack {
            // フォトピッカー（最大4枚、画像添付済みの場合は4枚未満のみ）
            PhotosPicker(
                selection: $photoPickerItems,
                maxSelectionCount: max(0, 4 - selectedImages.count),
                matching: .images
            ) {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundStyle(selectedImages.count >= 4 ? .tertiary : .secondary)
            }
            .disabled(selectedImages.count >= 4)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
