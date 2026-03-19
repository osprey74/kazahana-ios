// UserListView.swift
// kazahana-ios
// フォロワー / フォロー中ユーザー一覧画面

import SwiftUI

enum UserListType: Identifiable, Hashable {
    case followers(actor: String)
    case following(actor: String)

    var id: String { title + actor }

    var title: String {
        switch self {
        case .followers: return String(localized: "profile.followers")
        case .following: return String(localized: "profile.following")
        }
    }

    var actor: String {
        switch self {
        case .followers(let a), .following(let a): return a
        }
    }
}

struct UserListView: View {
    @Environment(AuthViewModel.self) private var authVM
    let listType: UserListType

    @State private var users: [ProfileViewBasic] = []
    @State private var cursor: String? = nil
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var selectedActor: IdentifiableString? = nil

    /// フォロー状態のローカルオーバーライド: [did: followURI or nil]
    @State private var followOverrides: [String: String?] = [:]

    var body: some View {
        Group {
            if isLoading && users.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, users.isEmpty {
                VStack(spacing: 12) {
                    Text(error).foregroundStyle(.secondary)
                    Button(String(localized: "profile.retry")) { Task { await loadInitial() } }
                        .buttonStyle(.bordered)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if users.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.slash")
                        .font(.largeTitle).foregroundStyle(.secondary)
                    Text(String(localized: "profile.noUsers")).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(users, id: \.did) { user in
                        HStack {
                            Button {
                                selectedActor = IdentifiableString(user.did)
                            } label: {
                                ActorRowView(actor: user)
                            }
                            .buttonStyle(.plain)

                            // 自分自身は非表示
                            if user.did != authVM.client.currentSession?.did {
                                followButton(for: user)
                            }
                        }
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

    // MARK: - フォローボタン

    @ViewBuilder
    private func followButton(for user: ProfileViewBasic) -> some View {
        let followURI = resolvedFollowURI(for: user)
        let isFollowing = followURI != nil

        Button {
            Task { await toggleFollow(user: user) }
        } label: {
            Text(isFollowing ? String(localized: "profile.following") : String(localized: "profile.follow"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(isFollowing ? Color.secondary : Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isFollowing ? Color.secondary.opacity(0.15) : Color.accentColor)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isFollowing ? Color.secondary.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    /// ローカルオーバーライドがあればそれを優先、なければ viewer.following を使う
    private func resolvedFollowURI(for user: ProfileViewBasic) -> String? {
        if let override = followOverrides[user.did] {
            return override
        }
        return user.viewer?.following
    }

    private func toggleFollow(user: ProfileViewBasic) async {
        let graphService = GraphService(client: authVM.client)
        let currentURI = resolvedFollowURI(for: user)

        if let uri = currentURI {
            // フォロー解除（楽観的UI）
            followOverrides[user.did] = .some(nil)
            do {
                try await graphService.unfollow(followUri: uri)
            } catch {
                followOverrides.removeValue(forKey: user.did)
            }
        } else {
            // フォロー（楽観的UI - まず仮のURIとしてnilでない値をセット）
            followOverrides[user.did] = .some("pending")
            do {
                let ref = try await graphService.follow(did: user.did)
                followOverrides[user.did] = .some(ref.uri)
            } catch {
                followOverrides.removeValue(forKey: user.did)
            }
        }
    }

    // MARK: - Data Loading

    private func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        cursor = nil
        hasMore = true
        let graphService = GraphService(client: authVM.client)
        do {
            let (fetched, nextCursor) = try await fetch(graphService: graphService, cursor: nil)
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
        let graphService = GraphService(client: authVM.client)
        do {
            let (fetched, nextCursor) = try await fetch(graphService: graphService, cursor: cursor)
            users.append(contentsOf: fetched)
            cursor = nextCursor
            hasMore = nextCursor != nil
        } catch {
            // ロードエラーはサイレント
        }
        isLoading = false
    }

    private func fetch(graphService: GraphService, cursor: String?) async throws -> ([ProfileViewBasic], String?) {
        switch listType {
        case .followers(let actor):
            let res = try await graphService.getFollowers(actor: actor, cursor: cursor)
            return (res.followers, res.cursor)
        case .following(let actor):
            let res = try await graphService.getFollows(actor: actor, cursor: cursor)
            return (res.follows, res.cursor)
        }
    }
}
