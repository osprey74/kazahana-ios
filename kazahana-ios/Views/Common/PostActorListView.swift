// PostActorListView.swift
// kazahana-ios
// 投稿にいいね／リポストしたユーザー一覧画面

import SwiftUI

enum PostActorListType: Identifiable, Hashable {
    case likes(postURI: String)
    case reposts(postURI: String)

    var id: String { title + postURI }

    var title: String {
        switch self {
        case .likes:   return "いいねしたユーザー"
        case .reposts: return "リポストしたユーザー"
        }
    }

    var postURI: String {
        switch self {
        case .likes(let uri), .reposts(let uri): return uri
        }
    }
}

struct PostActorListView: View {
    @Environment(AuthViewModel.self) private var authVM
    let listType: PostActorListType

    @State private var users: [ProfileViewBasic] = []
    @State private var cursor: String? = nil
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var selectedActor: IdentifiableString? = nil

    var body: some View {
        Group {
            if isLoading && users.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, users.isEmpty {
                VStack(spacing: 12) {
                    Text(error).foregroundStyle(.secondary)
                    Button("再試行") { Task { await loadInitial() } }
                        .buttonStyle(.bordered)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if users.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.slash")
                        .font(.largeTitle).foregroundStyle(.secondary)
                    Text("ユーザーはいません").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(users, id: \.did) { user in
                        Button {
                            selectedActor = IdentifiableString(user.did)
                        } label: {
                            ActorRowView(actor: user)
                        }
                        .buttonStyle(.plain)
                        .task {
                            if user.did == users.last?.did {
                                await loadMore()
                            }
                        }
                    }
                    if isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(listType.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedActor) { item in
            ProfileScreenView(actor: item.value)
                .environment(authVM)
        }
        .task { await loadInitial() }
    }

    // MARK: - Data Loading

    private func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        cursor = nil
        hasMore = true
        let postService = PostService(client: authVM.client)
        do {
            let (fetched, nextCursor) = try await fetch(postService: postService, cursor: nil)
            users = fetched
            cursor = nextCursor
            hasMore = nextCursor != nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        let postService = PostService(client: authVM.client)
        do {
            let (fetched, nextCursor) = try await fetch(postService: postService, cursor: cursor)
            users.append(contentsOf: fetched)
            cursor = nextCursor
            hasMore = nextCursor != nil
        } catch {}
        isLoading = false
    }

    private func fetch(postService: PostService, cursor: String?) async throws -> ([ProfileViewBasic], String?) {
        switch listType {
        case .likes(let uri):
            let res = try await postService.getLikes(uri: uri, cursor: cursor)
            return (res.likes.map { $0.actor }, res.cursor)
        case .reposts(let uri):
            let res = try await postService.getRepostedBy(uri: uri, cursor: cursor)
            return (res.repostedBy, res.cursor)
        }
    }
}
