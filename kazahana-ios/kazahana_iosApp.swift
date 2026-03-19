// kazahana_iosApp.swift
// kazahana-ios
// アプリエントリーポイント

import SwiftUI

@main
struct kazahana_iosApp: App {

    @State private var authViewModel = AuthViewModel()
    @State private var appSettings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authViewModel)
                .environment(appSettings)
                .preferredColorScheme(appSettings.theme.colorScheme)
        }
    }
}
