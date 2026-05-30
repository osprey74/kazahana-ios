// ContentView.swift
// kazahana-ios
// ルートビュー（認証状態によりログイン画面 or メイン画面を切り替え）

import SwiftUI

struct ContentView: View {

    @Environment(AuthViewModel.self) private var authVM

    var body: some View {
        if authVM.isLoggedIn {
            MainTabView(client: authVM.client)
                // アカウント切替時に全子ビューを再生成
                .id(authVM.activeAccountDID)
        } else if !authVM.savedAccounts.isEmpty {
            // 保存済みアカウントあり（複数 or トークン期限切れ）→ アカウント選択
            AccountPickerView()
        } else {
            LoginView()
        }
    }
}

// MARK: - メインタブ画面

/// macOS メニューバーからのタブ切替コマンドを中継する
@Observable
final class MenuCommandRelay {
    static let shared = MenuCommandRelay()
    /// 切替先タブと一意 ID のペア（ID により同じタブへの連続切替も検出可能）
    var tabCommand: (tab: MainTabView.Tab, id: UUID)? = nil

    func switchTo(_ tab: MainTabView.Tab) {
        tabCommand = (tab: tab, id: UUID())
    }
}

struct MainTabView: View {

    @Environment(AuthViewModel.self) private var authVM
    let client: ATProtoClient
    @State private var selectedTab: Tab = .home
    @State private var dmUnreadCount = 0
    /// Catalyst でプログラマティックなタブ切替時に TabView を強制再構築するための ID
    @State private var tabViewRefreshID = UUID()
    private let tabBarDelegate = TabBarDelegate()

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
                .desktopContent()
                .tabItem {
                    Label(String(localized: "tab.home"), systemImage: "house")
                }
                .tag(Tab.home)

            SearchView()
                .desktopContent()
                .tabItem {
                    Label(String(localized: "tab.search"), systemImage: "magnifyingglass")
                }
                .tag(Tab.search)

            NotificationListView()
                .desktopContent()
                .tabItem {
                    Label(String(localized: "tab.notifications"), systemImage: "bell")
                }
                .tag(Tab.notifications)

            ConversationListView(onUnreadCountChanged: { count in
                dmUnreadCount = count
            })
                .desktopContent()
                .tabItem {
                    Label(String(localized: "tab.messages"), systemImage: "envelope")
                }
                .badge(dmUnreadCount > 0 ? dmUnreadCount : 0)
                .tag(Tab.messages)

            // 自分のプロフィール
            selfProfileView
                .desktopContent()
                .tabItem {
                    Label(String(localized: "tab.profile"), systemImage: "person.circle")
                }
                .tag(Tab.profile)
        }
        .id(tabViewRefreshID)
        // iPad / macOS でも iPhone と同様に下部タブバーを表示するため compact に固定
        .environment(\.horizontalSizeClass, .compact)
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
        // アプリ起動時に BSAF Bot 定義の更新チェック
        .task {
            guard AppSettings.shared.bsafEnabled else { return }
            await BsafService.checkBotUpdates(settings: AppSettings.shared)
        }
        // App Store トランザクション更新を監視（IAP 購入完了を即時反映）
        .task {
            IAPService.shared.listenForTransactions(settings: AppSettings.shared)
        }
        // ホームタブの再タップを UITabBarControllerDelegate で検出
        .background(TabBarDelegateInjector(delegate: tabBarDelegate))
        // プッシュ通知タップ → 対象アカウントに切り替えて通知タブへ遷移
        .onReceive(NotificationCenter.default.publisher(for: .pushNotificationTapped)) { note in
            guard let targetDID = note.userInfo?["targetDID"] as? String else { return }
            Task {
                // 通知先アカウントが現在のアカウントと異なる場合は切り替え
                if authVM.activeAccountDID != targetDID,
                   let session = authVM.savedAccounts.first(where: { $0.did == targetDID }) {
                    await authVM.switchAccount(to: session)
                }
                await MainActor.run { selectedTab = .notifications }
            }
        }
        // macOS: メニューバーからのタブ切替（MenuCommandRelay 経由）
        .onChange(of: MenuCommandRelay.shared.tabCommand?.id) { _, _ in
            guard let command = MenuCommandRelay.shared.tabCommand else { return }
            selectedTab = command.tab
            // TabView の id を変更して強制再構築 → タブバー UI が確実に同期
            tabViewRefreshID = UUID()
        }
        // バッジをリセット（アプリ起動時）
        .task {
            PushNotificationService.shared.resetBadge()
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
            // ハッシュタグは検索タブに切り替え、タグ文字列を SearchView に通知
            if let tag = path.first, !tag.isEmpty {
                selectedTab = .search
                NotificationCenter.default.post(
                    name: .searchHashtag,
                    object: nil,
                    userInfo: ["tag": tag]
                )
            }
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

// MARK: - ホームタブ再タップ検出

/// UITabBarControllerDelegate を受け取り、ホームタブ（index 0）の再タップ時に
/// timelineScrollToTop 通知を送出する
final class TabBarDelegate: NSObject, UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        // index 0 = ホームタブ。selectedIndex が既に 0 の状態で再タップされたら通知を送出
        if tabBarController.selectedIndex == 0 {
            NotificationCenter.default.post(name: .timelineScrollToTop, object: nil)
        }
    }
}

/// UITabBarController に TabBarDelegate を注入するための UIViewControllerRepresentable
private struct TabBarDelegateInjector: UIViewControllerRepresentable {
    let delegate: TabBarDelegate

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // 親階層を遡って UITabBarController を探し、delegate を設定する
        DispatchQueue.main.async {
            var responder: UIResponder? = uiViewController
            while let next = responder?.next {
                if let tabBarController = next as? UITabBarController {
                    tabBarController.delegate = delegate
                    break
                }
                responder = next
            }
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

// MARK: - Desktop コンテンツ幅制約

private extension View {
    /// macOS Catalyst: コンテンツ幅を最大600pxに制約し中央揃え（Desktop版準拠）
    /// iOS: そのまま表示
    func desktopContent() -> some View {
        #if targetEnvironment(macCatalyst)
        self.frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        #else
        self
        #endif
    }
}

#Preview {
    ContentView()
        .environment(AuthViewModel())
}
