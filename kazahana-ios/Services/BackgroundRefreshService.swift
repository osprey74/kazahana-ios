// BackgroundRefreshService.swift
// kazahana-ios
// BGAppRefreshTask によるバックグラウンドポーリング（通知未読数チェック）

import Foundation
import BackgroundTasks
import UserNotifications

/// バックグラウンドリフレッシュのタスク識別子
enum BGTaskIdentifier {
    static let notificationRefresh = "com.osprey74.kazahana-ios.notificationRefresh"
}

/// バックグラウンドリフレッシュを管理するサービス
final class BackgroundRefreshService {

    static let shared = BackgroundRefreshService()
    private init() {}

    // MARK: - 登録

    /// Info.plist に登録済みのタスク識別子を BGTaskScheduler に登録する
    /// `application(_:didFinishLaunchingWithOptions:)` 相当のタイミングで呼ぶ
    func registerTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BGTaskIdentifier.notificationRefresh,
            using: nil
        ) { [weak self] task in
            guard let task = task as? BGAppRefreshTask else { return }
            self?.handleNotificationRefresh(task: task)
        }
    }

    // MARK: - スケジュール

    /// バックグラウンドリフレッシュをスケジュールする
    /// アプリがバックグラウンドに移行するタイミングで呼ぶ
    func scheduleNotificationRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: BGTaskIdentifier.notificationRefresh)
        // 最短15分後に実行（システムが適切なタイミングで実行する）
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - タスク処理

    private func handleNotificationRefresh(task: BGAppRefreshTask) {
        // 次回リフレッシュをスケジュール
        scheduleNotificationRefresh()

        // ATProtoClient は init 時に SessionStore から自動的にセッションを復元する
        let client = ATProtoClient(sessionStore: SessionStore())
        guard client.currentSession != nil else {
            // 未ログイン状態では処理不要
            task.setTaskCompleted(success: false)
            return
        }
        let notificationService = NotificationService(client: client)

        let fetchTask = Task {
            do {
                let count = try await notificationService.getUnreadCount()
                if count > 0 {
                    await sendLocalNotification(unreadCount: count)
                }
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }

        // BGTask のタイムリミットに合わせてキャンセル
        task.expirationHandler = {
            fetchTask.cancel()
        }
    }

    // MARK: - ローカル通知

    private func sendLocalNotification(unreadCount: Int) async {
        let center = UNUserNotificationCenter.current()

        // 通知許可を確認
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        // 既存の通知（同種）を削除して重複を防ぐ
        center.removePendingNotificationRequests(withIdentifiers: ["kazahana.notifications.unread"])
        center.removeDeliveredNotifications(withIdentifiers: ["kazahana.notifications.unread"])

        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.bg.title")
        content.body = String(format: String(localized: "notification.bg.body %lld"), unreadCount)
        content.sound = .default
        content.badge = NSNumber(value: unreadCount)

        let request = UNNotificationRequest(
            identifier: "kazahana.notifications.unread",
            content: content,
            trigger: nil  // 即時配信
        )
        try? await center.add(request)
    }
}
