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
    @State private var dmSearchHistory: [String] = []
    @Environment(\.dismiss) private var dismiss

    private static let historyKey = "dmUserSearchHistory"
    private static let historyLimit = 20

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowSeparator(.hidden)
                } else if searchText.isEmpty {
                    // 検索ワード未入力時は履歴表示
                    historySection
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(results, id: \.did) { actor in
                        Button {
                            addToHistory(searchText)
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
            .onAppear {
                loadHistory()
            }
        }
    }

    // MARK: - 履歴 UI

    @ViewBuilder
    private var historySection: some View {
        if dmSearchHistory.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "clock")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(String(localized: "search.noHistory"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            .listRowSeparator(.hidden)
        } else {
            Section {
                ForEach(dmSearchHistory, id: \.self) { term in
                    Button {
                        searchText = term
                    } label: {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text(term)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    deleteHistory(at: offsets)
                }
            } header: {
                HStack {
                    Text(String(localized: "search.history"))
                    Spacer()
                    Button(String(localized: "search.clearAll")) {
                        clearAllHistory()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - 履歴ロジック

    private func loadHistory() {
        dmSearchHistory = UserDefaults.standard.stringArray(forKey: Self.historyKey) ?? []
    }

    private func saveHistory() {
        UserDefaults.standard.set(dmSearchHistory, forKey: Self.historyKey)
    }

    private func addToHistory(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        dmSearchHistory.removeAll { $0 == trimmed }
        dmSearchHistory.insert(trimmed, at: 0)
        if dmSearchHistory.count > Self.historyLimit {
            dmSearchHistory = Array(dmSearchHistory.prefix(Self.historyLimit))
        }
        saveHistory()
    }

    private func deleteHistory(at offsets: IndexSet) {
        dmSearchHistory.remove(atOffsets: offsets)
        saveHistory()
    }

    private func clearAllHistory() {
        dmSearchHistory.removeAll()
        saveHistory()
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
