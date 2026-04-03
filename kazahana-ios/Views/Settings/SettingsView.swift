// SettingsView.swift
// kazahana-ios
// アプリ設定画面

import SwiftUI
import StoreKit

struct SettingsView: View {

    @Environment(AuthViewModel.self) private var authVM
    @Environment(AppSettings.self) private var settings
    @State private var showRestartAlert = false
    @State private var showRevokeApiKeyAlert = false
    @State private var iapService = IAPService.shared
    @State private var showAddAccount = false
    @State private var removeAccountTarget: Session? = nil

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

                // MARK: - BSAF
                Section {
                    Toggle(String(localized: "bsaf.enableBsaf"), isOn: $settings.bsafEnabled)

                    if settings.bsafEnabled {
                        NavigationLink {
                            BsafBotsView(client: authVM.client)
                                .environment(settings)
                        } label: {
                            Label(String(localized: "bsaf.manageBots"), systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }
                } header: {
                    Text(String(localized: "bsaf.title"))
                }

                // MARK: - サポーターバッジ
                Section {
                    // 有効期限表示
                    if settings.isSupporterBadgeActive, let expiry = settings.supporterBadgeExpiryDate {
                        LabeledContent(String(localized: "iap.expiresOn")) {
                            Text(expiry, style: .date)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(String(localized: "iap.notActive"))
                            .foregroundStyle(.secondary)
                    }

                    // 購入ボタン
                    if let product = iapService.product {
                        Button {
                            Task {
                                do {
                                    try await iapService.purchase(settings: settings)
                                } catch {
                                    iapService.purchaseError = error.localizedDescription
                                }
                            }
                        } label: {
                            if iapService.isPurchasing {
                                ProgressView()
                            } else {
                                Label(
                                    String(localized: "iap.purchase") + " (\(product.displayPrice))",
                                    systemImage: "medal.fill"
                                )
                            }
                        }
                        .disabled(iapService.isPurchasing || iapService.isRestoring)
                    } else if iapService.isLoadingProducts {
                        ProgressView()
                    } else {
                        // 商品取得失敗時：再試行ボタン
                        Button {
                            Task { await iapService.fetchProducts() }
                        } label: {
                            Label(String(localized: "iap.retry"), systemImage: "arrow.clockwise")
                        }
                    }

                    // リストアボタン
                    Button {
                        Task { await iapService.restorePurchases(settings: settings) }
                    } label: {
                        if iapService.isRestoring {
                            ProgressView()
                        } else {
                            Label(String(localized: "iap.restore"), systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(iapService.isPurchasing || iapService.isRestoring)

                    // エラーメッセージ
                    if let err = iapService.purchaseError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text(String(localized: "iap.title"))
                } footer: {
                    Text(String(localized: "iap.footer"))
                }
                .task {
                    if iapService.product == nil {
                        await iapService.fetchProducts()
                    }
                }

                // MARK: - アカウント管理
                Section {
                    ForEach(authVM.savedAccounts, id: \.did) { session in
                        SettingsAccountRow(session: session, isActive: session.did == authVM.activeAccountDID)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard session.did != authVM.activeAccountDID else { return }
                            Task { await authVM.switchAccount(to: session) }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                removeAccountTarget = session
                            } label: {
                                Label(String(localized: "auth.accountPicker.removeAccount"), systemImage: "trash")
                            }
                        }
                    }

                    Button {
                        showAddAccount = true
                    } label: {
                        Label(String(localized: "settings.addAccount"), systemImage: "plus.circle")
                    }
                } header: {
                    Text(String(localized: "settings.accounts"))
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
        .sheet(isPresented: $showAddAccount) {
            LoginView()
                .environment(authVM)
        }
        .confirmationDialog(
            String(localized: "auth.accountPicker.removeConfirmTitle"),
            isPresented: Binding(
                get: { removeAccountTarget != nil },
                set: { if !$0 { removeAccountTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "auth.accountPicker.removeAccount"), role: .destructive) {
                if let session = removeAccountTarget {
                    Task { await authVM.removeAccount(did: session.did) }
                    removeAccountTarget = nil
                }
            }
            Button(String(localized: "common.cancel"), role: .cancel) { removeAccountTarget = nil }
        } message: {
            Text(String(localized: "auth.accountPicker.removeConfirmMessage"))
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

private struct SettingsAccountRow: View {
    let session: Session
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(session.handle)")
                    .font(.subheadline)
                    .fontWeight(isActive ? .semibold : .regular)
                Text(session.did)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}
