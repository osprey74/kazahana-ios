// SearchView.swift
// kazahana-ios
// 検索画面

import SwiftUI

private struct IdentifiableActor: Identifiable, Hashable {
    let id: String  // DID or handle
}

struct SearchView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var viewModel: SearchViewModel?
    @State private var selectedActor: IdentifiableActor?
    @State private var selectedPostURI: IdentifiableString?
    /// タブ切り替え直後に通知が届いた場合に備えて保持するハッシュタグ
    @State private var pendingHashtag: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    searchContent(vm: vm)
                } else {
                    Color.clear
                }
            }
            .navigationTitle(String(localized: "tab.search"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedActor) { item in
                ProfileScreenView(actor: item.id)
                    .environment(authVM)
                    .navigationTitle(item.id)
            }
            .navigationDestination(item: $selectedPostURI) { item in
                ThreadView(uri: item.value, postService: PostService(client: authVM.client))
                    .environment(authVM)
            }
        }
        .onAppear {
            if viewModel == nil {
                let searchService = SearchService(client: authVM.client)
                viewModel = SearchViewModel(searchService: searchService)
            }
            // タブ切り替え前に受信した pendingHashtag があれば検索実行
            if let tag = pendingHashtag, let vm = viewModel {
                pendingHashtag = nil
                vm.query = "#\(tag)"
                vm.selectedTab = .posts
                Task { await vm.search() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .searchHashtag)) { note in
            guard let tag = note.userInfo?["tag"] as? String, !tag.isEmpty else { return }
            if let vm = viewModel {
                vm.query = "#\(tag)"
                vm.selectedTab = .posts  // ハッシュタグは投稿タブで検索
                Task { await vm.search() }
            } else {
                // viewModel 未初期化の場合は onAppear で処理
                pendingHashtag = tag
            }
        }
    }

    @ViewBuilder
    private func searchContent(vm: SearchViewModel) -> some View {
        VStack(spacing: 0) {
            if vm.query.isEmpty {
                // 検索履歴
                historyList(vm: vm)
            } else {
                // タブセレクター
                Picker("", selection: Binding(
                    get: { vm.selectedTab },
                    set: { tab in
                        vm.selectedTab = tab
                        Task { await vm.search() }
                    }
                )) {
                    ForEach(SearchTab.allCases) { tab in
                        Text(tab.displayName).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()

                // 検索結果
                switch vm.selectedTab {
                case .people:
                    actorList(vm: vm)
                case .posts:
                    postList(vm: vm)
                }
            }
        }
        .searchable(text: Binding(
            get: { vm.query },
            set: { vm.query = $0 }
        ), prompt: String(localized: "search.placeholder"))
        .onSubmit(of: .search) {
            Task { await vm.search() }
        }
        .onChange(of: vm.query) {
            if vm.query.isEmpty {
                vm.actors = []
                vm.posts = []
            }
        }
    }

    @ViewBuilder
    private func historyList(vm: SearchViewModel) -> some View {
        if vm.searchHistory.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "clock")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(String(localized: "search.noHistory"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    ForEach(vm.searchHistory, id: \.self) { term in
                        Button {
                            vm.query = term
                            Task { await vm.search() }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(term)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        vm.deleteHistory(at: offsets)
                    }
                } header: {
                    HStack {
                        Text(String(localized: "search.history"))
                        Spacer()
                        Button(String(localized: "search.clearAll")) {
                            vm.clearAllHistory()
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func actorList(vm: SearchViewModel) -> some View {
        if vm.isLoadingActors && vm.actors.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.actors.isEmpty {
            emptyState(vm: vm)
        } else {
            List {
                ForEach(vm.actors, id: \.did) { actor in
                    Button {
                        selectedActor = IdentifiableActor(id: actor.did)
                    } label: {
                        ActorRowView(actor: actor)
                    }
                    .buttonStyle(.plain)
                    .task {
                        if actor.did == vm.actors.last?.did {
                            await vm.loadMoreActors()
                        }
                    }
                }
                if vm.isLoadingActors {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func postList(vm: SearchViewModel) -> some View {
        if vm.isLoadingPosts && vm.posts.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.posts.isEmpty {
            emptyState(vm: vm)
        } else {
            List {
                ForEach(vm.posts) { post in
                    SearchPostRowView(
                        post: post,
                        onTapAuthor: { selectedActor = IdentifiableActor(id: post.author.did) }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedPostURI = IdentifiableString(post.uri)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .task {
                        if post.uri == vm.posts.last?.uri {
                            await vm.loadMorePosts()
                        }
                    }
                }
                if vm.isLoadingPosts {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func emptyState(vm: SearchViewModel) -> some View {
        if vm.query.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(String(localized: "search.hint"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(String(format: String(localized: "search.noResults"), vm.query))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - アクター行

struct ActorRowView: View {
    let actor: ProfileViewBasic

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: actor.avatar, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(actor.displayNameOrHandle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    if isBotAccount(did: actor.did, labels: actor.labels) {
                        BotBadge(size: 14)
                    }
                }
                Text("@\(actor.handle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 投稿検索行

struct SearchPostRowView: View {
    let post: PostView
    var onTapAuthor: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    onTapAuthor?()
                } label: {
                    AvatarView(url: post.author.avatar, size: 32)
                }
                .buttonStyle(.plain)
                Button {
                    onTapAuthor?()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.author.displayNameOrHandle)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("@\(post.author.handle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Text(post.indexedAt.relativeFormatted)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if !post.record.text.isEmpty {
                Text(post.record.text)
                    .font(.subheadline)
                    .lineLimit(4)
            }
        }
    }
}
