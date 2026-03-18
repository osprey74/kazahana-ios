// kazahana_iosApp.swift
// kazahana-ios
// アプリエントリーポイント

import SwiftUI

@main
struct kazahana_iosApp: App {

    @State private var authViewModel = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authViewModel)
        }
    }
}
