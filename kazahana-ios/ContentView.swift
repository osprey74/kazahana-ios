// ContentView.swift
// kazahana-ios
// ルートビュー（認証状態によりログイン画面 or メイン画面を切り替え）

import SwiftUI
import UserNotifications

struct ContentView: View {

    @Environment(AuthViewModel.self) private var authVM
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    #if !targetEnvironment(macCatalyst)
    /// 避難誘導用 LocationService（機能有効時のみ生成）
    @State private var locationService: LocationService?

    /// 避難所データストア
    @State private var shelterStore = ShelterStore()

    /// 避難誘導バナー状態管理（MainTabView の外で保持 → アカウント切替でも消えない）
    @State private var evacuationVM = EvacuationViewModel(settings: .shared)

    /// バナータップで避難所一覧を表示
    @State private var showEvacuationShelters = false

    /// 避難誘導オンボーディングダイアログ
    @State private var showEvacuationOnboarding = false
    #endif

    var body: some View {
        #if targetEnvironment(macCatalyst)
        mainContent
        #else
        mainContent
            // 避難誘導バナー（MainTabView の外側に overlay）
            .overlay(alignment: .bottom) {
                if evacuationVM.bannerVisible, let level = evacuationVM.highestLevel {
                    EvacuationBannerView(
                        highestLevel: level,
                        alertCount: evacuationVM.activeAlerts.count,
                        onTap: { showEvacuationShelters = true }
                    )
                    .padding(.bottom, 50) // タブバーの上に配置
                }
            }
            .animation(.easeInOut(duration: 0.3), value: evacuationVM.bannerVisible)
            .sheet(isPresented: $showEvacuationShelters) {
                NavigationStack {
                    NearestSheltersView(shelterIndex: shelterStore.index)
                        .environment(settings)
                        .environment(locationService)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(String(localized: "common.close")) {
                                    showEvacuationShelters = false
                                }
                            }
                        }
                }
            }
            // 避難誘導オンボーディング（初回のみ表示）
            .alert(String(localized: "evacuation.onboarding.title"), isPresented: $showEvacuationOnboarding) {
                Button(String(localized: "evacuation.onboarding.dismiss")) {
                    settings.evacuationOnboardingShown = true
                }
            } message: {
                Text(String(localized: "evacuation.onboarding.message"))
            }
            // 避難誘導関連を environment で配布
            .environment(locationService)
            .environment(shelterStore)
            .environment(evacuationVM)
            .onChange(of: settings.evacuationEnabled) { _, enabled in
                if enabled {
                    initializeEvacuationIfNeeded()
                } else {
                    evacuationVM.clearAll()
                }
            }
            .onAppear {
                if settings.evacuationEnabled {
                    initializeEvacuationIfNeeded()
                }
                // 初回のみオンボーディングダイアログを表示
                if !settings.evacuationOnboardingShown && !settings.evacuationEnabled {
                    showEvacuationOnboarding = true
                }
            }
            // フォアグラウンド復帰時にタイムアウト済みアラートを即座に除去
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active && settings.evacuationEnabled {
                    evacuationVM.expireStaleAlerts()
                }
            }
            // 10分間隔でタイムアウトチェック
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(600))
                    if settings.evacuationEnabled {
                        evacuationVM.expireStaleAlerts()
                    }
                }
            }
        #endif
    }

    /// メインコンテンツ（認証状態に応じた画面切り替え）
    private var mainContent: some View {
        Group {
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

    #if !targetEnvironment(macCatalyst)
    /// 避難誘導機能の初期化（LocationService + 避難所データ）
    private func initializeEvacuationIfNeeded() {
        if locationService == nil {
            locationService = LocationService()
        }
        shelterStore.loadIfNeeded()
    }
    #endif
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
    @State private var dmJoinRequestCount = 0
    #if targetEnvironment(macCatalyst)
    /// macOS: 前回の通知未読数（増加検出に使用）
    @State private var lastNotificationUnreadCount = 0
    #endif
    /// Catalyst でプログラマティックなタブ切替時に TabView を強制再構築するための ID
    @State private var tabViewRefreshID = UUID()
    private let tabBarDelegate = TabBarDelegate()

    // ディープリンクで開くプロフィールの actor (DID or handle)
    @State private var deepLinkProfileActor: String? = nil
    // ディープリンクで開く投稿スレッドの AT-URI
    @State private var deepLinkPostURI: IdentifiableString? = nil
    // ディープリンクで開く投稿作成画面の初期テキスト（kazahana://compose?text=...）
    @State private var deepLinkComposeText: IdentifiableString? = nil
    // ディープリンクで開くグループ参加画面の招待コード（kazahana://chat/{code}）
    @State private var deepLinkJoinCode: IdentifiableString? = nil

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

            ConversationListView(
                onUnreadCountChanged: { count in dmUnreadCount = count },
                onJoinRequestCountChanged: { count in dmJoinRequestCount = count }
            )
                .desktopContent()
                .tabItem {
                    Label(String(localized: "tab.messages"), systemImage: "envelope")
                }
                .badge(dmUnreadCount + dmJoinRequestCount > 0 ? dmUnreadCount + dmJoinRequestCount : 0)
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
        // ディープリンクでグループ参加画面を開く
        .sheet(item: $deepLinkJoinCode) { item in
            GroupJoinView(code: item.value)
                .environment(authVM)
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
        #if !targetEnvironment(macCatalyst)
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
        #endif
        // macOS: メニューバーからのタブ切替（MenuCommandRelay 経由）
        .onChange(of: MenuCommandRelay.shared.tabCommand?.id) { _, _ in
            guard let command = MenuCommandRelay.shared.tabCommand else { return }
            selectedTab = command.tab
        }
        // Mac Catalyst: プログラマティックなタブ切替時に TabView を強制再構築
        // → UITabBarController のチェックマーク表示を確実に同期させる
        .onChange(of: selectedTab) { _, _ in
            #if targetEnvironment(macCatalyst)
            tabViewRefreshID = UUID()
            #endif
        }
        #if !targetEnvironment(macCatalyst)
        // バッジをリセット（アプリ起動時）
        .task {
            PushNotificationService.shared.resetBadge()
        }
        #else
        // macOS: フォアグラウンドでの通知ポーリング（BGAppRefreshTask が使えないため）
        .task {
            await requestMacNotificationPermission()
            let notificationService = NotificationService(client: client)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                do {
                    let count = try await notificationService.getUnreadCount()
                    if count > lastNotificationUnreadCount && count > 0 {
                        await sendMacLocalNotification(unreadCount: count)
                    }
                    lastNotificationUnreadCount = count
                } catch {
                    // ポーリングエラーはサイレント
                }
            }
        }
        #endif
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
            // Share Extension / Edge共有 から起動
            // ?text= : Share Extension 経由（テキスト直接指定）
            // ?title=...&url=... : Edge 等のブラウザ共有（Windows版互換）
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let queryItems = components?.queryItems ?? []
            let textParam = queryItems.first(where: { $0.name == "text" })?.value
            let titleParam = queryItems.first(where: { $0.name == "title" })?.value
            let urlParam = queryItems.first(where: { $0.name == "url" })?.value

            let composeText: String
            if let text = textParam, !text.isEmpty {
                composeText = text
            } else if let title = titleParam, let shareURL = urlParam {
                composeText = title + "\n" + shareURL
            } else if let shareURL = urlParam {
                composeText = shareURL
            } else {
                composeText = ""
            }
            deepLinkComposeText = IdentifiableString(value: composeText)
        case "chat":
            // グループ招待リンク: kazahana://chat/{code}
            if let code = path.first, !code.isEmpty {
                deepLinkJoinCode = IdentifiableString(value: code)
            }
        default:
            break
        }
    }

    #if targetEnvironment(macCatalyst)
    /// macOS: 通知権限をリクエスト
    private func requestMacNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    /// macOS: ローカル通知を送信
    private func sendMacLocalNotification(unreadCount: Int) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        // 既存の通知を削除して重複を防ぐ
        center.removePendingNotificationRequests(withIdentifiers: ["kazahana.mac.notifications.unread"])
        center.removeDeliveredNotifications(withIdentifiers: ["kazahana.mac.notifications.unread"])

        let content = UNMutableNotificationContent()
        content.title = "kazahana"
        content.body = String(format: String(localized: "notification.bg.body %lld"), unreadCount)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "kazahana.mac.notifications.unread",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
    #endif

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
