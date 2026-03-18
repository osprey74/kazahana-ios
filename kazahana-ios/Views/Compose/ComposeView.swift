// ComposeView.swift
// kazahana-ios
// 投稿作成画面（新規投稿・リプライ対応）

import SwiftUI

struct ComposeView: View {

    @Environment(\.dismiss) private var dismiss

    // テキストは View の @State で直接管理（@Observable ViewModel の TextEditor バインディング問題を回避）
    @State private var text: String = ""
    @State private var isPosting = false
    @State private var errorMessage: String? = nil

    private let postService: PostService
    private let replyToPost: PostView?
    private let replyTarget: ReplyTarget?
    private let quotePost: PostView?

    init(postService: PostService, replyTo: PostView? = nil, quotedPost: PostView? = nil) {
        self.postService = postService
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
    private var canPost: Bool { graphemeCount > 0 && remaining >= 0 && !isPosting }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // リプライ先プレビュー
                if let replyTo = replyToPost {
                    replyPreview(post: replyTo)
                    Divider()
                }

                // 入力エリア
                TextEditor(text: $text)
                    .font(.body)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 12)
                    .scrollContentBackground(.hidden)

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
            let detected = RichTextParser.detectFacets(in: text)
            let facets = RichTextParser.buildFacets(from: detected)
            _ = try await postService.createPost(
                text: text,
                facets: facets.isEmpty ? nil : facets,
                replyTo: replyTarget,
                quotePost: quotePost
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isPosting = false
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

    private var bottomBar: some View {
        HStack {
            Image(systemName: "photo")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .opacity(0.5)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
