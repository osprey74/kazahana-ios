// SettingsView.swift
// kazahana-ios
// アプリ設定画面

import SwiftUI

struct SettingsView: View {

    @Environment(AuthViewModel.self) private var authVM
    @Environment(AppSettings.self) private var settings
    @State private var showRestartAlert = false
    @State private var showRevokeApiKeyAlert = false

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                // MARK: - 表示設定
                Section(String(localized: "settings.display")) {
                    Picker(String(localized: "settings.theme"), selection: $settings.theme) {
                        ForEach(AppSettings.Theme.allCases, id: \.self) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    Picker(String(localized: "settings.pollingInterval"), selection: $settings.timelinePollingInterval) {
                        ForEach(AppSettings.PollingInterval.allCases, id: \.self) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }
                }

                // MARK: - 言語設定
                Section {
                    Picker(String(localized: "settings.postLanguage"), selection: $settings.postLanguageSetting) {
                        ForEach(AppSettings.PostLanguage.allCases, id: \.self) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .onChange(of: settings.postLanguageSetting) {
                        showRestartAlert = true
                    }
                    Toggle(String(localized: "settings.showVia"), isOn: $settings.showVia)
                } header: {
                    Text(String(localized: "settings.post"))
                } footer: {
                    Text(String(localized: "settings.postLanguageFooter"))
                }
                .alert(String(localized: "settings.restartRequired"), isPresented: $showRestartAlert) {
                    Button(String(localized: "settings.restartAction")) { showRestartAlert = false }
                } message: {
                    Text(String(localized: "settings.restartMessage"))
                }

                // MARK: - コンテンツモデレーション
                Section {
                    Toggle(String(localized: "settings.adultContent"), isOn: $settings.adultContentEnabled)
                } header: {
                    Text(String(localized: "settings.moderation"))
                } footer: {
                    Text(String(localized: "settings.adultContentFooter"))
                }

                if settings.adultContentEnabled {
                    Section(String(localized: "settings.adultContentSection")) {
                        moderationPicker(String(localized: "moderation.porn"), key: "porn", settings: $settings)
                        moderationPicker(String(localized: "moderation.sexual"), key: "sexual", settings: $settings)
                        moderationPicker(String(localized: "moderation.nudity"), key: "nudity", settings: $settings)
                    }
                }

                Section(String(localized: "settings.graphicContent")) {
                    moderationPicker(String(localized: "moderation.graphicMedia"), key: "graphic-media", settings: $settings)
                    moderationPicker(String(localized: "moderation.gore"), key: "gore", settings: $settings)
                }

                // MARK: - Claude API
                Section {
                    SecureField("sk-ant-...", text: $settings.claudeApiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !settings.claudeApiKey.isEmpty {
                        Button(role: .destructive) {
                            showRevokeApiKeyAlert = true
                        } label: {
                            Label(String(localized: "settings.claudeApiRevoke"), systemImage: "key.slash")
                        }
                        .alert(String(localized: "settings.claudeApiRevoke"), isPresented: $showRevokeApiKeyAlert) {
                            Button(String(localized: "settings.claudeApiRevoke"), role: .destructive) {
                                settings.claudeApiKey = ""
                            }
                            Button(String(localized: "common.cancel"), role: .cancel) {}
                        } message: {
                            Text(String(localized: "settings.claudeApiRevokeMessage"))
                        }
                    }
                } header: {
                    Text(String(localized: "settings.claudeApi"))
                } footer: {
                    Text(String(localized: "settings.claudeApiFooter"))
                }

                // MARK: - ホームフィード管理
                Section(String(localized: "settings.feedManagement")) {
                    NavigationLink {
                        FeedManagementView(
                            client: authVM.client,
                            actorDID: authVM.client.currentSession?.did ?? ""
                        )
                        .environment(settings)
                    } label: {
                        Label(String(localized: "settings.feedManagement"), systemImage: "square.stack")
                    }
                }

                // MARK: - アカウント
                Section(String(localized: "settings.account")) {
                    if let session = authVM.client.currentSession {
                        LabeledContent(String(localized: "settings.handle"), value: "@\(session.handle)")
                        LabeledContent("DID", value: session.did)
                            .font(.caption)
                    }

                    Button(role: .destructive) {
                        Task { await authVM.logout() }
                    } label: {
                        Label(String(localized: "settings.logout"), systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                // MARK: - アプリ情報
                Section(String(localized: "settings.appInfo")) {
                    LabeledContent(String(localized: "settings.version"), value: appVersion)
                    LabeledContent("Bluesky", value: "@app-kazahana.bsky.social")
                }
            }
            .navigationTitle(String(localized: "settings.title"))
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
