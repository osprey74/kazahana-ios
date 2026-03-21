// ContentView.swift
// kazahana-ios
// ルートビュー（認証状態によりログイン画面 or メイン画面を切り替え）

import SwiftUI

struct ContentView: View {

    @Environment(AuthViewModel.self) private var authVM

    var body: some View {
        if authVM.isLoggedIn {
            MainTabView(client: authVM.client)
        } else {
            LoginView()
        }
    }
}

// MARK: - メインタブ画面

struct MainTabView: View {

    @Environment(AuthViewModel.self) private var authVM
    let client: ATProtoClient
    @State private var selectedTab: Tab = .home
    @State private var dmUnreadCount = 0

    // ディープリンクで開くプロフィールの actor (DID or handle)
    @State private var deepLinkProfileActor: String? = nil
    // ディープリンクで開く投稿スレッドの AT-URI
    @State private var deepLinkPostURI: IdentifiableString? = nil
    // ディープリンクで開く投稿作成画面の初期テキスト（kazahana://compose?text=...）
    @State private var deepLinkComposeText: IdentifiableString? = nil

    enum Tab {
        case home, search, notifications, messages, profile
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TimelineView(client: client)
                .tabItem {
                    Label(String(localized: "tab.home"), systemImage: "house")
                }
                .tag(Tab.home)

            SearchView()
                .tabItem {
                    Label(String(localized: "tab.search"), systemImage: "magnifyingglass")
                }
                .tag(Tab.search)

            NotificationListView()
                .tabItem {
                    Label(String(localized: "tab.notifications"), systemImage: "bell")
                }
                .tag(Tab.notifications)

            ConversationListView(onUnreadCountChanged: { count in
                dmUnreadCount = count
            })
                .tabItem {
                    Label(String(localized: "tab.messages"), systemImage: "envelope")
                }
                .badge(dmUnreadCount > 0 ? dmUnreadCount : 0)
                .tag(Tab.messages)

            // 自分のプロフィール
            selfProfileView
                .tabItem {
                    Label(String(localized: "tab.profile"), systemImage: "person.circle")
                }
                .tag(Tab.profile)
        }
        // ディープリンクでプロフィール遷移（home タブに表示）
        .sheet(item: Binding(
            get: { deepLinkProfileActor.map { IdentifiableString(value: $0) } },
            set: { deepLinkProfileActor = $0?.value }
        )) { item in
            NavigationStack {
                ProfileScreenView(actor: item.value)
            }
            .environment(authVM)
        }
        // ディープリンクでスレッド遷移
        .sheet(item: $deepLinkPostURI) { item in
            if let postService = authVM.isLoggedIn ? PostService(client: authVM.client) : nil {
                NavigationStack {
                    ThreadView(uri: item.value, postService: postService)
                }
                .environment(authVM)
            }
        }
        // ディープリンクで投稿作成画面を開く（Share Extension 経由）
        .sheet(item: $deepLinkComposeText) { item in
            if let postService = authVM.isLoggedIn ? PostService(client: authVM.client) : nil {
                ComposeView(postService: postService, initialText: item.value)
                    .environment(authVM)
                    .environment(AppSettings.shared)
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        // PostCardView 内の openURL ハンドラーから転送される kazahana:// リンクを受信
        .onReceive(NotificationCenter.default.publisher(for: .kazahanaDeepLink)) { note in
            if let url = note.userInfo?["url"] as? URL {
                handleDeepLink(url)
            }
        }
    }

    /// kazahana:// ディープリンクを処理する
    /// - kazahana://profile/{did_or_handle}
    /// - kazahana://post/{at_uri_encoded}
    /// - kazahana://hashtag/{tag} → 検索タブへ
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "kazahana" else { return }
        let host = url.host ?? ""
        let path = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "profile":
            if let actor = path.first, !actor.isEmpty {
                deepLinkProfileActor = actor
            }
        case "post":
            // AT-URI は URL エンコードされて渡ってくる想定
            if let encoded = path.first,
               let decoded = encoded.removingPercentEncoding {
                deepLinkPostURI = IdentifiableString(value: decoded)
            }
        case "hashtag":
            // ハッシュタグは検索タブに切り替え（将来的に検索クエリを渡す実装で拡張）
            selectedTab = .search
        case "compose":
            // Share Extension から起動: ?text= クエリパラメータを投稿エリアに渡す
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let text = components?.queryItems?.first(where: { $0.name == "text" })?.value ?? ""
            deepLinkComposeText = IdentifiableString(value: text)
        default:
            break
        }
    }

    @ViewBuilder
    private var selfProfileView: some View {
        if let did = client.currentSession?.did {
            NavigationStack {
                ProfileScreenView(actor: did)
                    .navigationTitle(String(localized: "tab.profile"))
            }
        } else {
            PlaceholderView(title: String(localized: "tab.profile"), icon: "person.circle")
        }
    }
}

// MARK: - プレースホルダー（Phase 4以降に置き換え）

struct PlaceholderView: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(String(localized: "dm.comingSoon"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(title)
    }
}

#Preview {
    ContentView()
        .environment(AuthViewModel())
}
