// CreateGroupView.swift
// kazahana-ios
// グループ作成画面（グループ名 + メンバー選択）

import SwiftUI

struct CreateGroupView: View {
    @Environment(AuthViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss

    let chatService: ChatService
    let onGroupCreated: (ConvoView) -> Void

    @State private var groupName = ""
    @State private var selectedMembers: [ProfileViewBasic] = []
    @State private var searchText = ""
    @State private var searchResults: [ProfileViewBasic] = []
    @State private var isSearching = false
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    private var canCreate: Bool {
        !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !selectedMembers.isEmpty
            && !isCreating
    }

    var body: some View {
        NavigationStack {
            List {
                // グループ名
                Section(String(localized: "dm.createGroup.nameSection")) {
                    TextField(String(localized: "dm.createGroup.namePlaceholder"), text: $groupName)
                        .textInputAutocapitalization(.never)
                }

                // 選択済みメンバー
                if !selectedMembers.isEmpty {
                    Section(String(localized: "dm.createGroup.membersSection \(selectedMembers.count)")) {
                        ForEach(selectedMembers, id: \.did) { member in
                            HStack(spacing: 12) {
                                AvatarView(url: member.avatar, size: 36)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(member.displayNameOrHandle)
                                        .font(.callout)
                                        .fontWeight(.medium)
                                    Text("@\(member.handle)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    selectedMembers.removeAll { $0.did == member.did }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // メンバー検索
                Section(String(localized: "dm.createGroup.addMembers")) {
                    TextField(String(localized: "dm.searchUser"), text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: searchText) { _, newValue in
                            scheduleSearch(query: newValue)
                        }

                    if isSearching {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    }

                    ForEach(searchResults, id: \.did) { actor in
                        let isSelected = selectedMembers.contains { $0.did == actor.did }
                        Button {
                            toggleMember(actor)
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(url: actor.avatar, size: 36)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(actor.displayNameOrHandle)
                                        .font(.callout)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                    Text("@\(actor.handle)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .disabled(selectedMembers.count >= 49 && !isSelected)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(String(localized: "dm.createGroup.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await createGroup() }
                    } label: {
                        if isCreating {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text(String(localized: "dm.createGroup.create"))
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!canCreate)
                }
            }
            .alert(String(localized: "common.error"), isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button(String(localized: "common.ok")) { errorMessage = nil }
            } message: {
                if let msg = errorMessage { Text(msg) }
            }
        }
    }

    // MARK: - Actions

    private func toggleMember(_ actor: ProfileViewBasic) {
        if let idx = selectedMembers.firstIndex(where: { $0.did == actor.did }) {
            selectedMembers.remove(at: idx)
        } else if selectedMembers.count < 49 {
            selectedMembers.append(actor)
        }
    }

    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        searchTask = Task {
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
            searchResults = response.actors.filter { $0.did != authVM.client.currentSession?.did }
        } catch {
            searchResults = []
        }
        isSearching = false
    }

    @MainActor
    private func createGroup() async {
        let name = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !selectedMembers.isEmpty else { return }
        isCreating = true
        do {
            let memberDIDs = selectedMembers.map(\.did)
            let convo = try await chatService.createGroup(name: name, memberDIDs: memberDIDs)
            onGroupCreated(convo)
        } catch {
            errorMessage = error.localizedDescription
        }
        isCreating = false
    }
}
