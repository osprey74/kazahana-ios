// NewConversationView.swift
// kazahana-ios
// 新規会話作成画面（ユーザー検索 → 会話開始）

import SwiftUI

struct NewConversationView: View {
    @Environment(AuthViewModel.self) private var authVM
    let chatService: ChatService
    let onConvoCreated: (ConvoView) -> Void

    @State private var searchText = ""
    @State private var results: [ProfileViewBasic] = []
    @State private var isSearching = false
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowSeparator(.hidden)
                } else if results.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(results, id: \.did) { actor in
                        Button {
                            startConversation(with: actor)
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(url: actor.avatar, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(actor.displayNameOrHandle)
                                        .font(.callout)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                    Text("@\(actor.handle)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isCreating {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .disabled(isCreating)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                }
            }
            .listStyle(.plain)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: String(localized: "dm.searchUser")
            )
            .onChange(of: searchText) { _, newValue in
                scheduleSearch(query: newValue)
            }
            .navigationTitle(String(localized: "dm.newConversation"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }
            }
            .alert(String(localized: "common.error"), isPresented: .constant(errorMessage != nil)) {
                Button(String(localized: "common.ok")) { errorMessage = nil }
            } message: {
                if let msg = errorMessage { Text(msg) }
            }
        }
    }

    // MARK: - Search

    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            results = []
            return
        }
        searchTask = Task {
            // 200ms デバウンス
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await performSearch(query: query)
        }
    }

    @MainActor
    private func performSearch(query: String) async {
        isSearching = true
        let searchService = SearchService(client: authVM.client)
        do {
            let response = try await searchService.searchActorsTypeahead(query: query, limit: 20)
            // 自分自身を除外
            results = response.actors.filter { $0.did != authVM.client.currentSession?.did }
        } catch {
            results = []
        }
        isSearching = false
    }

    // MARK: - 会話作成

    private func startConversation(with actor: ProfileViewBasic) {
        guard !isCreating else { return }
        guard let myDID = authVM.client.currentSession?.did else { return }
        isCreating = true
        Task {
            do {
                let convo = try await chatService.getConvoForMembers(memberDIDs: [myDID, actor.did])
                await MainActor.run {
                    isCreating = false
                    onConvoCreated(convo)
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
