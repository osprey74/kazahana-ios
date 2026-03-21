// kazahana_iosApp.swift
// kazahana-ios
// アプリエントリーポイント

import SwiftUI
import BackgroundTasks

@main
struct kazahana_iosApp: App {

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
        }
    }
}
