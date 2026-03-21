// BsafBotsView.swift
// kazahana-ios
// BSAF 対応 Bot 管理画面（登録・解除・フィルタ設定）

import SwiftUI

struct BsafBotsView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AuthViewModel.self) private var authVM

    private let graphService: GraphService

    @State private var urlInput: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil
    @State private var expandedDid: String? = nil
    @State private var confirmUnregisterDid: String? = nil

    init(client: ATProtoClient) {
        self.graphService = GraphService(client: client)
    }

    var body: some View {
        List {
            // 登録セクション
            registrationSection

            // 登録済み Bot 一覧
            if settings.bsafRegisteredBots.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label(String(localized: "bsaf.noBots"),
                              systemImage: "antenna.radiowaves.left.and.right.slash")
                    }
                }
            } else {
                ForEach(settings.bsafRegisteredBots) { bot in
                    botSection(bot)
                }
            }
        }
        .navigationTitle(String(localized: "bsaf.manageTitle"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 登録セクション

    @ViewBuilder
    private var registrationSection: some View {
        Section {
            HStack {
                TextField(String(localized: "bsaf.urlPlaceholder"), text: $urlInput)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)

                Button(String(localized: "bsaf.fetch")) {
                    Task { await handleFetchUrl() }
                }
                .disabled(urlInput.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }

            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            }

            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let success = successMessage {
                Label(success, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        } header: {
            Text(String(localized: "bsaf.title"))
        }
    }

    // MARK: - Bot セクション（アコーディオン）

    @ViewBuilder
    private func botSection(_ bot: BsafRegisteredBot) -> some View {
        let isExpanded = expandedDid == bot.definition.bot.did

        Section {
            // ヘッダー行（タップで展開/折りたたみ）
            Button {
                withAnimation { expandedDid = isExpanded ? nil : bot.definition.bot.did }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bot.definition.bot.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("@\(bot.definition.bot.handle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            // 展開時のコンテンツ
            if isExpanded {
                // 説明文
                Text(bot.definition.bot.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // 動的フィルタグループ
                ForEach(bot.definition.filters, id: \.tag) { filter in
                    filterGroup(bot: bot, filter: filter)
                }

                // Bot 情報
                botInfoRows(bot)

                // 登録解除ボタン
                unregisterControl(bot)
            }
        }
    }

    // MARK: - フィルタグループ（チップトグル）

    @ViewBuilder
    private func filterGroup(bot: BsafRegisteredBot, filter: BsafFilter) -> some View {
        let enabled = bot.filterSettings[filter.tag] ?? []
        let did = bot.definition.bot.did

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(filter.label)
                    .font(.caption.weight(.medium))
                Spacer()
                Button(String(localized: "bsaf.selectAll")) {
                    settings.setFilterOptions(
                        did: did, tag: filter.tag,
                        values: filter.options.map { $0.value }
                    )
                }
                .font(.caption2)
                .foregroundStyle(Color.accentColor)

                Button(String(localized: "bsaf.deselectAll")) {
                    settings.setFilterOptions(did: did, tag: filter.tag, values: [])
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            WrappingHStack(alignment: .leading, spacing: 6) {
                ForEach(filter.options, id: \.value) { option in
                    let isEnabled = enabled.contains(option.value)
                    Button {
                        var current = enabled
                        if isEnabled {
                            current.removeAll { $0 == option.value }
                        } else {
                            current.append(option.value)
                        }
                        settings.setFilterOptions(did: did, tag: filter.tag, values: current)
                    } label: {
                        Text(option.label)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                isEnabled ? Color.accentColor : Color.secondary.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                            .foregroundStyle(isEnabled ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Bot 情報行

    @ViewBuilder
    private func botInfoRows(_ bot: BsafRegisteredBot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            LabeledContent(String(localized: "bsaf.source"),
                           value: bot.definition.bot.source)
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent(String(localized: "bsaf.lastUpdated"),
                           value: formatDate(bot.definition.updatedAt))
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent(String(localized: "bsaf.lastChecked"),
                           value: formatDate(bot.lastCheckedAt))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 登録解除コントロール

    @ViewBuilder
    private func unregisterControl(_ bot: BsafRegisteredBot) -> some View {
        let did = bot.definition.bot.did
        if confirmUnregisterDid == did {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "bsaf.unregisterConfirm"))
                    .font(.caption)
                    .foregroundStyle(.orange)
                HStack(spacing: 12) {
                    Button(String(localized: "bsaf.unregister"), role: .destructive) {
                        Task { await handleUnregister(did: did) }
                    }
                    .font(.caption)
                    Button(String(localized: "compose.cancel"), role: .cancel) {
                        confirmUnregisterDid = nil
                    }
                    .font(.caption)
                }
            }
        } else {
            Button(role: .destructive) {
                confirmUnregisterDid = did
            } label: {
                Label(String(localized: "bsaf.unregister"), systemImage: "trash")
                    .font(.caption)
            }
        }
    }

    // MARK: - アクション

    private func handleFetchUrl() async {
        let trimmed = urlInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        errorMessage = nil
        successMessage = nil
        isLoading = true

        do {
            let definition = try await BsafService.fetchBotDefinition(from: trimmed)

            // 重複チェック
            if settings.bsafRegisteredBots.contains(where: {
                $0.definition.bot.did == definition.bot.did
            }) {
                errorMessage = BsafError.duplicateBot.localizedDescription
                isLoading = false
                return
            }

            // 登録
            settings.registerBot(definition)

            // 自動フォロー
            do {
                _ = try await graphService.follow(did: definition.bot.did)
            } catch {
                successMessage = String(localized: "bsaf.followFailed")
                isLoading = false
                urlInput = ""
                return
            }

            successMessage = String(localized: "bsaf.registered")
            urlInput = ""
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func handleUnregister(did: String) async {
        errorMessage = nil

        // 自動アンフォロー
        do {
            let profile = try await graphService.getProfile(actor: did)
            if let followUri = profile.viewer?.following {
                try await graphService.unfollow(followUri: followUri)
            }
        } catch {
            // アンフォロー失敗は無視して登録解除を続行
        }

        settings.unregisterBot(did: did)
        confirmUnregisterDid = nil
        if expandedDid == did { expandedDid = nil }
        successMessage = String(localized: "bsaf.unregistered")
    }

    // MARK: - ヘルパー

    private func formatDate(_ iso: String) -> String {
        var formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: iso)
        if date == nil {
            formatter = ISO8601DateFormatter()
            date = formatter.date(from: iso)
        }
        guard let date else { return iso }
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .none
        return display.string(from: date)
    }
}
