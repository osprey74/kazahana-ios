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
        // BGAppRefreshTask タスクを登録（アプリ起動時に必ず呼ぶ必要がある）
        BackgroundRefreshService.shared.registerTasks()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authViewModel)
                .environment(appSettings)
                .preferredColorScheme(appSettings.theme.colorScheme)
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
        }
    }
}

// MARK: - AppDelegate（APNs コールバック + UNUserNotificationCenterDelegate）

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // フォアグラウンドでもプッシュ通知を表示するためにデリゲートを設定
        UNUserNotificationCenter.current().delegate = self
        return true
    }

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

    /// フォアグラウンド表示中にプッシュ通知を受け取ったときの表示設定
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
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
}
