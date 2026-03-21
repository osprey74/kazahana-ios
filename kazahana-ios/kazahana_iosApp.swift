// kazahana_iosApp.swift
// kazahana-ios
// アプリエントリーポイント

import SwiftUI
import BackgroundTasks

@main
struct kazahana_iosApp: App {

    @State private var authViewModel = AuthViewModel()
    @State private var appSettings = AppSettings.shared

    private static let suiteName  = "group.com.osprey74.kazahana-ios"
    private static let pendingKey = "shareExtension.pendingText"

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
                // フォアグラウンド復帰時に Share Extension からのペンディングテキストを処理
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.willEnterForegroundNotification
                    )
                ) { _ in
                    checkPendingShareText()
                }
                // アプリ起動時（コールドスタート）にも確認
                .onAppear {
                    checkPendingShareText()
                }
        }
    }

    /// Share Extension が App Groups に書き込んだテキストを取り出し、
    /// kazahana://compose?text=... として handleDeepLink に渡す
    private func checkPendingShareText() {
        guard let defaults = UserDefaults(suiteName: Self.suiteName),
              let text = defaults.string(forKey: Self.pendingKey),
              !text.isEmpty else { return }

        // 読み取ったら即座に削除（二重起動を防ぐ）
        defaults.removeObject(forKey: Self.pendingKey)
        defaults.synchronize()

        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "kazahana://compose?text=\(encoded)") else { return }

        NotificationCenter.default.post(
            name: .kazahanaDeepLink,
            object: nil,
            userInfo: ["url": url]
        )
    }
}
