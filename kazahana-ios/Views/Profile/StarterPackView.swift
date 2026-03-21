// StarterPackView.swift
// kazahana-ios
// スターターパック一覧・詳細表示

import SwiftUI

/// プロフィールのスターターパックタブ（一覧）
struct StarterPackListTabView: View {
    @Environment(AuthViewModel.self) private var authVM
    let actor: String

    @State private var starterPacks: [StarterPackViewBasic] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    private var feedService: FeedService {
        FeedService(client: authVM.client)
    }

    var body: some View {
        Group {
            if isLoading && starterPacks.isEmpty {
                ProgressView().padding(.top, 32)
            } else if let error = errorMessage, starterPacks.isEmpty {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 40)
                    .frame(maxWidth: .infinity)
            } else if starterPacks.isEmpty {
                Text(String(localized: "profile.noStarterPacks"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 40)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(starterPacks) { pack in
                    NavigationLink {
                        StarterPackDetailView(uri: pack.uri)
                            .environment(authVM)
                    } label: {
                        starterPackRow(pack: pack)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 16)
                }
            }
        }
        .task { await load() }
    }

    private func starterPackRow(pack: StarterPackViewBasic) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(pack.record.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let desc = pack.record.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 12) {
                    if let count = pack.listItemCount {
                        Label("\(count)", systemImage: "person")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let joined = pack.joinedAllTimeCount {
                        Label("\(joined)", systemImage: "arrow.right.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @MainActor
    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let response = try await feedService.getActorStarterPacks(actor: actor)
            starterPacks = response.starterPacks
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

/// スターターパック詳細画面
struct StarterPackDetailView: View {
    @Environment(AuthViewModel.self) private var authVM
    let uri: String

    @State private var starterPack: StarterPackView? = nil
    @State private var members: [ListItemView] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var selectedAuthorDID: IdentifiableString? = nil

    private var feedService: FeedService {
        FeedService(client: authVM.client)
    }

    var body: some View {
        Group {
            if isLoading && starterPack == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, starterPack == nil {
                errorView(message: error)
            } else if let pack = starterPack {
                detailContent(pack: pack)
            }
        }
        .navigationTitle(starterPack?.record.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .navigationDestination(item: $selectedAuthorDID) { item in
            ProfileScreenView(actor: item.value)
                .environment(authVM)
        }
    }

    private func detailContent(pack: StarterPackView) -> some View {
        List {
            // 説明セクション
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if let desc = pack.record.description, !desc.isEmpty {
                        Text(desc)
                            .font(.subheadline)
                    }
                    HStack(spacing: 16) {
                        if let count = pack.listItemCount {
                            Label("\(count)", systemImage: "person")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let joined = pack.joinedAllTimeCount {
                            Label(String(format: String(localized: "starterPack.joinedAllTime"), joined), systemImage: "arrow.right.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text(pack.record.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }

            // メンバー一覧
            if !members.isEmpty {
                Section(header: Text(String(localized: "starterPack.members")).textCase(nil)) {
                    ForEach(members, id: \.uri) { item in
                        Button {
                            selectedAuthorDID = IdentifiableString(item.subject.did)
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(url: item.subject.avatar, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.subject.displayNameOrHandle)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text("@\(item.subject.handle)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(String(localized: "feed.retry")) {
                Task { await load() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let packResponse = try await feedService.getStarterPack(uri: uri)
            starterPack = packResponse.starterPack
            // メンバー一覧：スターターパックに紐付くリストのメンバーを取得
            if let listURI = packResponse.starterPack.list?.uri {
                let membersResponse = try await feedService.getListMembers(listURI: listURI)
                members = membersResponse.items
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
