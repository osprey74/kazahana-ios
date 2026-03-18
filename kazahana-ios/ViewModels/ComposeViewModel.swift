// ComposeViewModel.swift
// kazahana-ios
// 投稿作成 ViewModel

import SwiftUI
import Observation

@Observable
final class ComposeViewModel {

    // MARK: - State

    var text: String = ""
    var isPosting: Bool = false
    var errorMessage: String? = nil
    var didPost: Bool = false

    // 返信先（リプライ時に設定）
    var replyTarget: ReplyTarget? = nil
    var replyToPost: PostView? = nil

    // 文字数（300 grapheme cluster 単位）
    var graphemeCount: Int { text.count }
    var remaining: Int { 300 - graphemeCount }
    var isOverLimit: Bool { remaining < 0 }
    var canPost: Bool { graphemeCount > 0 && !isOverLimit && !isPosting }

    // MARK: - Dependencies

    private let postService: PostService

    // MARK: - Init

    init(postService: PostService) {
        self.postService = postService
    }

    // MARK: - Actions

    func post() async {
        guard canPost else { return }
        isPosting = true
        errorMessage = nil

        do {
            // Facet 自動検出（メンションの DID 解決は非同期だが今回はリンク・ハッシュタグのみ自動解決）
            let detected = RichTextParser.detectFacets(in: text)
            let facets = RichTextParser.buildFacets(from: detected)
            let finalFacets = facets.isEmpty ? nil : facets

            _ = try await postService.createPost(
                text: text,
                facets: finalFacets,
                replyTo: replyTarget
            )
            didPost = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isPosting = false
    }
}
