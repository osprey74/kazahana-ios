// SettingsView.swift
// kazahana-ios
// アプリ設定画面

import SwiftUI
import StoreKit

struct SettingsView: View {

    @Environment(AuthViewModel.self) private var authVM
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var showRestartAlert = false
    @State private var showRevokeApiKeyAlert = false
    @State private var iapService = IAPService.shared
    @State private var showAddAccount = false
    @State private var removeAccountTarget: Session? = nil
    @State private var chatDeclaration: ChatDeclaration?
    @State private var isLoadingChatSettings = false

    #if !targetEnvironment(macCatalyst)
    @Environment(ShelterStore.self) private var shelterStore: ShelterStore?
    @Environment(EvacuationViewModel.self) private var evacuationVM: EvacuationViewModel?
    @State private var showEvacuationBotConfirm = false
    @State private var evacuationBotRegistering = false
    @State private var evacuationBotError: String? = nil
    @State private var demoModeTapCount = 0
    @State private var showDemoMode = false
    #endif

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

                // MARK: - 長文投稿サービス
                Section {
                    TextField("https://", text: $settings.longFormServiceUrl)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !settings.longFormServiceUrl.isEmpty {
                        Button(role: .destructive) {
                            settings.longFormServiceUrl = ""
                        } label: {
                            Label(String(localized: "settings.longformServiceUrlDelete"), systemImage: "trash")
                        }
                    }
                } header: {
                    Text(String(localized: "settings.longformServiceUrl"))
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "settings.longformServiceUrlFooter"))
                        Link("standard.site", destination: URL(string: "https://standard.site")!)
                    }
                }

                // MARK: - ウォーターマーク
                Section {
                    NavigationLink {
                        WatermarkSettingsView()
                            .environment(settings)
                    } label: {
                        HStack {
                            Label(String(localized: "watermark.title"), systemImage: "signature")
                            Spacer()
                            if settings.watermarkSettings.enabled {
                                Text(String(localized: "watermark.statusOn"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // MARK: - 画像表示モード
                Section(String(localized: "settings.imageOpenMode")) {
                    Picker(String(localized: "settings.imageOpenMode"), selection: $settings.imageOpenMode) {
                        ForEach(AppSettings.ImageOpenMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                }

                // MARK: - 下書き設定
                Section(String(localized: "settings.draftImageWarning")) {
                    Toggle(String(localized: "settings.enableDraftImageWarning"),
                           isOn: $settings.confirmDraftImageQuality)
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

                // MARK: - チャット設定
                chatSettingsSection

                // MARK: - 避難誘導機能（iOS のみ）
                #if !targetEnvironment(macCatalyst)
                evacuationSection
                #endif

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
                        HStack {
                            SettingsAccountRow(session: session, isActive: session.did == authVM.activeAccountDID)

                            // × ボタン（Windows 版と同じパターン）
                            Button {
                                removeAccountTarget = session
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color(.tertiaryLabel))
                            }
                            .buttonStyle(.borderless)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard session.did != authVM.activeAccountDID, !authVM.isSwitchingAccount else { return }
                            Task { await authVM.switchAccount(to: session) }
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

                // MARK: - macOS 専用設定
                #if targetEnvironment(macCatalyst)
                Section(String(localized: "settings.macOS")) {
                    Toggle(String(localized: "settings.launchAtLogin"), isOn: $settings.launchAtLogin)
                        .onChange(of: settings.launchAtLogin) { _, newValue in
                            MacLoginItemHelper.setEnabled(newValue)
                        }
                    Picker(String(localized: "settings.closeAction"), selection: $settings.closeButtonAction) {
                        ForEach(AppSettings.CloseButtonAction.allCases, id: \.self) { action in
                            Text(action.displayName).tag(action)
                        }
                    }
                }
                #endif

                // MARK: - アプリ情報
                Section(String(localized: "settings.appInfo")) {
                    #if targetEnvironment(macCatalyst)
                    LabeledContent(String(localized: "settings.version"), value: appVersion)
                    #else
                    LabeledContent(String(localized: "settings.version"), value: appVersion)
                        .onTapGesture {
                            demoModeTapCount += 1
                            if demoModeTapCount >= 5 {
                                showDemoMode.toggle()
                                demoModeTapCount = 0
                            }
                        }
                    #endif
                    LabeledContent("Bluesky", value: "@kazahana.app")
                }
            }
            .navigationTitle(String(localized: "settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.close")) {
                        dismiss()
                    }
                }
            }
        }
        .overlay {
            if authVM.isSwitchingAccount {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.3)
                        .tint(.white)
                    Text(String(localized: "auth.switchingAccount"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
                .background(.ultraThinMaterial.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
            }
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

    // MARK: - チャット設定セクション

    @ViewBuilder
    private var chatSettingsSection: some View {
        Section {
            if isLoadingChatSettings {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else {
                Picker(String(localized: "settings.allowGroupInvites"), selection: Binding(
                    get: { chatDeclaration?.allowGroupInvites ?? "all" },
                    set: { newValue in
                        chatDeclaration?.allowGroupInvites = newValue
                        Task { await saveChatDeclaration() }
                    }
                )) {
                    Text(String(localized: "settings.allowGroupInvites.all")).tag("all")
                    Text(String(localized: "settings.allowGroupInvites.following")).tag("following")
                    Text(String(localized: "settings.allowGroupInvites.none")).tag("none")
                }
            }
        } header: {
            Text(String(localized: "settings.chatSection"))
        } footer: {
            Text(String(localized: "settings.allowGroupInvitesHint"))
        }
        .task {
            await loadChatDeclaration()
        }
    }

    @MainActor
    private func loadChatDeclaration() async {
        isLoadingChatSettings = true
        let svc = ChatService(client: authVM.client)
        do {
            chatDeclaration = try await svc.getChatDeclaration()
        } catch {
            chatDeclaration = ChatDeclaration()
        }
        isLoadingChatSettings = false
    }

    @MainActor
    private func saveChatDeclaration() async {
        guard let declaration = chatDeclaration else { return }
        let svc = ChatService(client: authVM.client)
        try? await svc.updateChatDeclaration(declaration)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    #if !targetEnvironment(macCatalyst)
    // MARK: - 避難誘導セクション

    @ViewBuilder
    private var evacuationSection: some View {
        Section {
            Toggle(String(localized: "evacuation.enable"), isOn: Binding(
                get: { settings.evacuationEnabled },
                set: { newValue in
                    if newValue {
                        // bsaf-kikikuru-bot が未登録なら確認ダイアログを表示
                        if !isKikikuruBotRegistered {
                            showEvacuationBotConfirm = true
                        } else {
                            settings.evacuationEnabled = true
                            settings.bsafEnabled = true
                        }
                    } else {
                        settings.evacuationEnabled = false
                    }
                }
            ))
            .disabled(evacuationBotRegistering)

            if settings.evacuationEnabled {
                Picker(String(localized: "evacuation.prefectureOverride"),
                       selection: Binding(
                        get: { settings.evacuationPrefectureOverride },
                        set: { settings.evacuationPrefectureOverride = $0 }
                       )) {
                    Text(String(localized: "evacuation.prefectureAuto")).tag(nil as String?)
                    ForEach(Prefecture.allCases, id: \.self) { pref in
                        Text(pref.displayName).tag(pref.rawValue as String?)
                    }
                }

                NavigationLink {
                    NearestSheltersView(shelterIndex: shelterStore?.index ?? [:])
                        .environment(settings)
                } label: {
                    Label(String(localized: "evacuation.nearestShelters"),
                          systemImage: "building.2")
                }
            }

            // デモモード（バージョン番号5回タップで表示）
            if showDemoMode {
                // モック Bot 登録で強制有効化
                if !settings.evacuationEnabled {
                    Button {
                        let mockDef = BsafBotDefinition(
                            bsafSchema: "bsaf-bot-v1",
                            updatedAt: ISO8601DateFormatter().string(from: Date()),
                            selfUrl: AppSettings.kikikuruBotDefinitionUrl,
                            bot: BsafBotInfo(
                                handle: "bsaf-kikikuru-bot.bsky.social",
                                did: "did:plc:debug-kikikuru-bot",
                                name: "bsaf-kikikuru-bot",
                                description: "気象庁キキクル（危険度分布）の情報を BSAF 形式で配信する Bot（デモ用モック）",
                                source: "jma",
                                sourceUrl: nil
                            ),
                            filters: [
                                BsafFilter(tag: "target", label: "対象地域", options:
                                    Prefecture.allCases.map { BsafFilterOption(value: $0.rawValue, label: $0.displayName) }
                                ),
                                BsafFilter(tag: "value", label: "レベル", options: [
                                    BsafFilterOption(value: "level3", label: "レベル3（警報級）"),
                                    BsafFilterOption(value: "level4", label: "レベル4（危険）"),
                                    BsafFilterOption(value: "level5", label: "レベル5（特別警報級）"),
                                ])
                            ]
                        )
                        if settings.findRegisteredBot(did: mockDef.bot.did) == nil {
                            settings.registerBot(mockDef)
                        }
                        settings.bsafEnabled = true
                        settings.evacuationEnabled = true
                        settings.evacuationPrefectureOverride = "jp-tokyo"
                        evacuationBotError = nil
                    } label: {
                        Label("Demo: Force Enable (mock bot)", systemImage: "forward.fill")
                    }
                    .foregroundStyle(.purple)
                }

                // アラートシミュレーション
                if let evacuationVM {
                    Button {
                        evacuationVM.injectTestAlert(level: .level3)
                    } label: {
                        Label("Demo: Level 3 Alert", systemImage: "ant")
                    }
                    .foregroundStyle(.orange)

                    Button {
                        evacuationVM.injectTestAlert(level: .level4, type: "flood-warning")
                    } label: {
                        Label("Demo: Level 4 Alert", systemImage: "ant.fill")
                    }
                    .foregroundStyle(.red)

                    Button {
                        evacuationVM.injectTestAlert(level: .level5, type: "landslide-warning")
                    } label: {
                        Label("Demo: Level 5 Alert", systemImage: "ant.circle.fill")
                    }
                    .foregroundStyle(.pink)

                    if evacuationVM.bannerVisible {
                        Button(role: .destructive) {
                            evacuationVM.clearAll()
                        } label: {
                            Label("Demo: Clear All Alerts", systemImage: "trash")
                        }
                    }
                }
            }

            if evacuationBotRegistering {
                HStack { Spacer(); ProgressView(); Spacer() }
            }

            if let error = evacuationBotError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text(String(localized: "evacuation.title"))
        } footer: {
            Text(String(localized: "evacuation.footer"))
        }
        .alert(String(localized: "evacuation.botConfirm.title"), isPresented: $showEvacuationBotConfirm) {
            Button(String(localized: "evacuation.botConfirm.enable")) {
                Task { await registerKikikuruBotAndEnable() }
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "evacuation.botConfirm.message"))
        }
    }

    /// bsaf-kikikuru-bot が登録済みかチェック
    private var isKikikuruBotRegistered: Bool {
        settings.bsafRegisteredBots.contains { bot in
            bot.definition.selfUrl == AppSettings.kikikuruBotDefinitionUrl
                || BsafService.toRawUrl(bot.definition.selfUrl) == BsafService.toRawUrl(AppSettings.kikikuruBotDefinitionUrl)
        }
    }

    /// bsaf-kikikuru-bot を自動登録して避難誘導機能を有効化
    private func registerKikikuruBotAndEnable() async {
        evacuationBotRegistering = true
        evacuationBotError = nil
        do {
            let definition = try await BsafService.fetchBotDefinition(
                from: AppSettings.kikikuruBotDefinitionUrl
            )

            // 重複チェック
            if settings.findRegisteredBot(did: definition.bot.did) != nil {
                // 既に登録済みならそのまま有効化
                await MainActor.run {
                    settings.bsafEnabled = true
                    settings.evacuationEnabled = true
                    evacuationBotRegistering = false
                }
                return
            }

            await MainActor.run {
                settings.registerBot(definition)
                settings.bsafEnabled = true
                settings.evacuationEnabled = true
            }

            // 自動フォロー（BsafBotsView と同じパターン）
            let graphService = GraphService(client: authVM.client)
            _ = try await graphService.follow(did: definition.bot.did)
        } catch {
            await MainActor.run {
                evacuationBotError = error.localizedDescription
            }
        }
        await MainActor.run {
            evacuationBotRegistering = false
        }
    }
    #endif
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
