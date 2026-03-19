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
                    Text("オンにすると投稿レコードに $via: \"\(settings.viaName)\" が付与されます。")
                }

                // MARK: - コンテンツモデレーション
                Section {
                    Toggle("成人向けコンテンツを表示", isOn: $settings.adultContentEnabled)
                } header: {
                    Text("コンテンツモデレーション")
                } footer: {
                    Text("オフの場合、成人向けコンテンツは常に非表示になります。")
                }

                if settings.adultContentEnabled {
                    Section("成人向けコンテンツ") {
                        moderationPicker("ポルノ", key: "porn", settings: $settings)
                        moderationPicker("性的コンテンツ", key: "sexual", settings: $settings)
                        moderationPicker("ヌード", key: "nudity", settings: $settings)
                    }
                }

                Section("過激コンテンツ") {
                    moderationPicker("グロテスク画像", key: "graphic-media", settings: $settings)
                    moderationPicker("暴力的画像", key: "gore", settings: $settings)
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

    @ViewBuilder
    private func moderationPicker(_ label: String, key: String, settings: Bindable<AppSettings>) -> some View {
        let binding = Binding<AppSettings.ModerationBehavior>(
            get: { settings.wrappedValue.labelPreferences[key] ?? .warn },
            set: { settings.wrappedValue.labelPreferences[key] = $0 }
        )
        Picker(label, selection: binding) {
            ForEach(AppSettings.ModerationBehavior.allCases, id: \.self) { behavior in
                Text(behavior.displayName).tag(behavior)
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
