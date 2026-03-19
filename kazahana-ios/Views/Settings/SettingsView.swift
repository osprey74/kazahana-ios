// SettingsView.swift
// kazahana-ios
// アプリ設定画面

import SwiftUI

struct SettingsView: View {

    @Environment(AuthViewModel.self) private var authVM
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                // MARK: - 表示設定
                Section("表示") {
                    Picker("テーマ", selection: $settings.theme) {
                        ForEach(AppSettings.Theme.allCases, id: \.self) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                }

                // MARK: - 投稿設定
                Section {
                    Toggle("投稿元を表示（via）", isOn: $settings.showVia)
                } header: {
                    Text("投稿")
                } footer: {
                    Text("オンにすると投稿に「\(settings.viaName)」というクライアント名が付与されます。")
                }

                // MARK: - アカウント
                Section("アカウント") {
                    if let session = authVM.client.currentSession {
                        LabeledContent("ハンドル", value: "@\(session.handle)")
                        LabeledContent("DID", value: session.did)
                            .font(.caption)
                    }

                    Button(role: .destructive) {
                        Task { await authVM.logout() }
                    } label: {
                        Label("ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                // MARK: - アプリ情報
                Section("アプリ情報") {
                    LabeledContent("バージョン", value: appVersion)
                    LabeledContent("Bluesky", value: "@app-kazahana.bsky.social")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
