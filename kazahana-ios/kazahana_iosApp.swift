// kazahana_iosApp.swift
// kazahana-ios
// アプリエントリーポイント

import SwiftUI
import BackgroundTasks
import UserNotifications

@main
struct kazahana_iosApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var authViewModel = AuthViewModel()
    @State private var appSettings = AppSettings.shared

    init() {
        #if !targetEnvironment(macCatalyst)
        // BGAppRefreshTask タスクを登録（アプリ起動時に必ず呼ぶ必要がある）
        BackgroundRefreshService.shared.registerTasks()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authViewModel)
                .environment(appSettings)
                .preferredColorScheme(appSettings.theme.colorScheme)
                #if !targetEnvironment(macCatalyst)
                // バックグラウンド移行時にリフレッシュをスケジュール
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.didEnterBackgroundNotification
                    )
                ) { _ in
                    BackgroundRefreshService.shared.scheduleNotificationRefresh()
                }
                // フォアグラウンド復帰時にバッジをリセット
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.willEnterForegroundNotification
                    )
                ) { _ in
                    PushNotificationService.shared.resetBadge()
                }
                #endif
        }
    }
}

// MARK: - AppDelegate（APNs コールバック + UNUserNotificationCenterDelegate）

final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // フォアグラウンドでも通知を表示するためにデリゲートを設定
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    #if targetEnvironment(macCatalyst)
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = MacSceneDelegate.self
        return config
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .main else { return }

        // File > New Post (Cmd+N)
        let newPost = UIKeyCommand(
            title: String(localized: "menu.newPost"),
            action: #selector(handleNewPost),
            input: "N",
            modifierFlags: .command
        )

        // View > Reload (Cmd+R)
        let reload = UIKeyCommand(
            title: String(localized: "menu.reload"),
            action: #selector(handleReload),
            input: "R",
            modifierFlags: .command
        )
        let viewMenu = UIMenu(title: String(localized: "menu.view"), children: [reload])

        // Window > タブ切替 (Cmd+1〜5)
        let tabMenu = UIMenu(title: "", options: .displayInline, children: [
            UIKeyCommand(title: String(localized: "tab.home"), action: #selector(handleTab1), input: "1", modifierFlags: .command),
            UIKeyCommand(title: String(localized: "tab.search"), action: #selector(handleTab2), input: "2", modifierFlags: .command),
            UIKeyCommand(title: String(localized: "tab.notifications"), action: #selector(handleTab3), input: "3", modifierFlags: .command),
            UIKeyCommand(title: String(localized: "tab.messages"), action: #selector(handleTab4), input: "4", modifierFlags: .command),
            UIKeyCommand(title: String(localized: "tab.profile"), action: #selector(handleTab5), input: "5", modifierFlags: .command),
        ])

        // File > Submit Post (Option+Return) — Desktop版 (Alt+Enter) と統一
        let submitPost = UIKeyCommand(
            title: String(localized: "menu.submitPost"),
            action: #selector(handleSubmitPost),
            input: "\r",
            modifierFlags: .alternate
        )

        // 既存の File メニューに New Post / Submit Post を追加
        builder.insertChild(UIMenu(title: "", options: .displayInline, children: [newPost, submitPost]), atStartOfMenu: .file)

        // View メニューを追加
        builder.insertSibling(viewMenu, afterMenu: .file)

        // Window メニューにタブ切替を追加
        builder.insertChild(tabMenu, atEndOfMenu: .window)
    }

    @objc func handleNewPost() {
        NotificationCenter.default.post(name: .composeNewPost, object: nil)
    }

    @objc func handleSubmitPost() {
        NotificationCenter.default.post(name: .composeSubmitPost, object: nil)
    }


    @objc func handleReload() {
        NotificationCenter.default.post(name: .reloadTimeline, object: nil)
    }

    @objc func handleTab1() { MenuCommandRelay.shared.switchTo(.home) }
    @objc func handleTab2() { MenuCommandRelay.shared.switchTo(.search) }
    @objc func handleTab3() { MenuCommandRelay.shared.switchTo(.notifications) }
    @objc func handleTab4() { MenuCommandRelay.shared.switchTo(.messages) }
    @objc func handleTab5() { MenuCommandRelay.shared.switchTo(.profile) }
    #endif

    /// フォアグラウンド表示中に通知を受け取ったときの表示設定（iOS/macOS共通）
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }

    #if !targetEnvironment(macCatalyst)
    /// APNs からデバイストークンを受け取ったときに呼ばれる
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushNotificationService.shared.didReceiveDeviceToken(deviceToken)
    }

    /// APNs 登録が失敗したときに呼ばれる
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[Push] Failed to register for remote notifications: \(error)")
    }

    /// ユーザーが通知をタップしたときに呼ばれる
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let targetDID = userInfo["target_did"] as? String else { return }
        // NotificationCenter 経由で ContentView/MainTabView に通知
        NotificationCenter.default.post(
            name: .pushNotificationTapped,
            object: nil,
            userInfo: ["targetDID": targetDID]
        )
    }
    #endif
}

// MARK: - macOS ウィンドウサイズ制御・閉じるボタン動作

#if targetEnvironment(macCatalyst)
import ServiceManagement

/// 設定画面から呼び出すログインアイテム登録ヘルパー
enum MacLoginItemHelper {
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            print("[LaunchAtLogin] \(error)")
        }
    }
}

final class MacSceneDelegate: UIResponder, UIWindowSceneDelegate {

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // Desktop 版準拠: 最小 400×600
        windowScene.sizeRestrictions?.minimumSize = CGSize(width: 400, height: 600)

        // 初回のみデフォルトサイズ 480×800 を設定
        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            let geometryPreferences = UIWindowScene.GeometryPreferences.Mac(
                systemFrame: CGRect(x: 0, y: 0, width: 480, height: 800)
            )
            windowScene.requestGeometryUpdate(geometryPreferences)
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        }

        // タイトルバーのスタイル調整
        if let titlebar = windowScene.titlebar {
            titlebar.titleVisibility = .hidden
            titlebar.toolbar = nil
        }

        // 閉じるボタン動作
        setupCloseButtonBehavior(for: windowScene)

        // ログインアイテム同期
        syncLoginItem()

        // NSWindow の frameAutosaveName を設定（AppKit が自動で位置・サイズを保存・復元）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let nsWindow = windowScene.windows.first?.value(forKey: "hostWindow") as? NSObject else { return }
            nsWindow.perform(NSSelectorFromString("setFrameAutosaveName:"), with: "kazahanaMainWindow")
        }
    }

    /// Dock アイコンクリック時にウィンドウを復元
    func sceneDidBecomeActive(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene else { return }
        for window in windowScene.windows {
            window.makeKeyAndVisible()
        }
    }

    /// 閉じるボタンの動作を設定に応じて制御
    private func setupCloseButtonBehavior(for windowScene: UIWindowScene) {
        // 閉じるボタン動作の監視（設定変更時に即座に反映）
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyCloseButtonBehavior(for: windowScene)
        }
    }

    private func applyCloseButtonBehavior(for windowScene: UIWindowScene) {
        // Mac Catalyst では windowScene.session.role で制御
        // 「最小化」モードの場合はシーンの破棄を抑制
    }

    /// OS 起動時自動スタートの登録/解除
    private func syncLoginItem() {
        let settings = AppSettings.shared
        do {
            if settings.launchAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            print("[LaunchAtLogin] \(error)")
        }
    }
}
#endif
