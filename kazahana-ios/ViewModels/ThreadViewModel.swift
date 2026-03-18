// ThreadViewModel.swift
// kazahana-ios
// スレッド表示 ViewModel

import SwiftUI
import Observation

@Observable
final class ThreadViewModel {

    var thread: ThreadViewPost? = nil
    var isLoading: Bool = false
    var errorMessage: String? = nil

    private let postService: PostService
    let rootURI: String

    init(postService: PostService, uri: String) {
        self.postService = postService
        self.rootURI = uri
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let response = try await postService.getThread(uri: rootURI)
            thread = response.thread
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
