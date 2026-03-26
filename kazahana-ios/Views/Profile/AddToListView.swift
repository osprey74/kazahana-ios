// AddToListView.swift
// kazahana-ios
// リストへのユーザー追加/削除シート

import SwiftUI

struct AddToListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthViewModel.self) private var authVM

    let targetDid: String
    let graphService: GraphService

    @State private var lists: [GraphListView] = []
    @State private var memberships: [String: String] = [:]  // [listUri: listitemUri]
    @State private var isLoading = true
    @State private var processingListUri: String? = nil
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if lists.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "profile.noLists"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(lists) { list in
                        listRow(list)
                    }
                }
            }
            .navigationTitle(String(localized: "profile.addToList"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.close")) { dismiss() }
                }
            }
            .alert(String(localized: "common.error"), isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button(String(localized: "common.ok"), role: .cancel) { errorMessage = nil }
            } message: {
                if let msg = errorMessage { Text(msg) }
            }
        }
        .task {
            await load()
        }
    }

    @ViewBuilder
    private func listRow(_ list: GraphListView) -> some View {
        let isMember = memberships[list.uri] != nil
        let isProcessing = processingListUri == list.uri

        HStack(spacing: 12) {
            if let avatarURL = list.avatar, let url = URL(string: avatarURL) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            } else {
                Image(systemName: "list.bullet.rectangle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(Color(.systemGray5), in: Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                if let count = list.listItemCount {
                    Text(String(format: String(localized: "profile.listMemberCount"), count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isProcessing {
                ProgressView()
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: isMember ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title2)
                    .foregroundStyle(isMember ? Color.accentColor : Color.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isProcessing else { return }
            Task { await toggleMembership(list: list) }
        }
    }

    private func load() async {
        isLoading = true
        do {
            async let listsTask = graphService.getMyLists()
            async let membershipsTask = graphService.getListMemberships(targetDid: targetDid)
            (lists, memberships) = try await (listsTask, membershipsTask)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func toggleMembership(list: GraphListView) async {
        processingListUri = list.uri
        do {
            if let listitemUri = memberships[list.uri] {
                try await graphService.removeFromList(listitemUri: listitemUri)
                memberships.removeValue(forKey: list.uri)
            } else {
                let uri = try await graphService.addToList(targetDid: targetDid, listUri: list.uri)
                memberships[list.uri] = uri
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        processingListUri = nil
    }
}
