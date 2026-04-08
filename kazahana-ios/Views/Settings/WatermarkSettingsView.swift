// WatermarkSettingsView.swift
// kazahana-ios
// ウォーターマーク設定画面

import SwiftUI

struct WatermarkSettingsView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AuthViewModel.self) private var authVM
    // HEX 入力フィールドのローカル state（途中入力でストアを更新しないよう分離）
    @State private var hexInput: String = ""
    // リアルタイムプレビュー画像
    @State private var previewImage: UIImage? = nil

    var body: some View {
        @Bindable var settings = settings

        Form {
            // MARK: - ON/OFF
            Section {
                Toggle(String(localized: "watermark.enable"), isOn: $settings.watermarkSettings.enabled)
            } footer: {
                Text(String(localized: "watermark.hint"))
            }

            if settings.watermarkSettings.enabled {

                // MARK: - リアルタイムプレビュー
                Section(String(localized: "watermark.preview")) {
                    if let preview = previewImage {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else if let base = UIImage(named: "watermark-preview") {
                        Image(uiImage: base)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                // 設定変更のたびにプレビューを再生成
                .task(id: settings.watermarkSettings) {
                    await updatePreview(wm: settings.watermarkSettings)
                }

                // MARK: - 文言プリセット
                Section(String(localized: "watermark.preset")) {
                    Picker(String(localized: "watermark.preset"), selection: $settings.watermarkSettings.preset) {
                        ForEach(WatermarkPreset.allCases, id: \.self) { preset in
                            Text(preset.localizedLabel).tag(preset)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    if settings.watermarkSettings.preset == .custom {
                        VStack(alignment: .leading, spacing: 4) {
                            TextEditor(text: $settings.watermarkSettings.customText)
                                .autocorrectionDisabled()
                                .frame(minHeight: 64)
                                .onChange(of: settings.watermarkSettings.customText) { _, new in
                                    if new.count > 100 {
                                        settings.watermarkSettings.customText = String(new.prefix(100))
                                    }
                                }
                            Text(String(localized: "watermark.customHint"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // MARK: - 表示位置
                Section(String(localized: "watermark.position")) {
                    positionGrid(selection: $settings.watermarkSettings.position)
                }

                // MARK: - 不透明度・文字サイズ
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "watermark.opacity"))
                            Spacer()
                            Text("\(Int(settings.watermarkSettings.opacity))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: $settings.watermarkSettings.opacity,
                            in: 20...100,
                            step: 5
                        )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "watermark.fontSize"))
                            Spacer()
                            Text("\(Int(settings.watermarkSettings.fontSize))px")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: $settings.watermarkSettings.fontSize,
                            in: 8...20,
                            step: 1
                        )
                        Text(String(localized: "watermark.fontSizeHint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: - 文字色
                Section(String(localized: "watermark.textColor")) {
                    colorPalette(selection: $settings.watermarkSettings.textColor)
                    HStack {
                        Text("#")
                            .foregroundStyle(.secondary)
                        TextField("FFFFFF", text: $hexInput)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                            .onChange(of: hexInput) { _, new in
                                let cleaned = new.uppercased().filter { $0.isHexDigit }.prefix(6)
                                let val = String(cleaned)
                                if val.count == 6 {
                                    settings.watermarkSettings.textColor = "#\(val)"
                                }
                                if hexInput != val { hexInput = val }
                            }
                        Spacer()
                        // カラープレビュー
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: settings.watermarkSettings.textColor) ?? .white)
                            .frame(width: 28, height: 28)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
                .onAppear {
                    hexInput = settings.watermarkSettings.textColor
                        .uppercased()
                        .replacingOccurrences(of: "#", with: "")
                }
                .onChange(of: settings.watermarkSettings.textColor) { _, new in
                    let val = new.uppercased().replacingOccurrences(of: "#", with: "")
                    if hexInput != val { hexInput = val }
                }

                // MARK: - 投稿オプション
                Section {
                    Toggle(String(localized: "watermark.confirmBeforePost"),
                           isOn: $settings.watermarkSettings.confirmBeforePost)
                    Toggle(String(localized: "watermark.skipVideo"),
                           isOn: $settings.watermarkSettings.skipVideo)
                }
            }
        }
        .navigationTitle(String(localized: "watermark.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - プレビュー生成

    @MainActor
    private func updatePreview(wm: WatermarkSettings) async {
        guard let base = UIImage(named: "watermark-preview") else { return }
        let handle = authVM.client.currentSession?.handle ?? "example.bsky.social"
        previewImage = WatermarkService.apply(to: base, settings: wm, handle: handle)
    }

    // MARK: - 位置選択グリッド（3×2）

    @ViewBuilder
    private func positionGrid(selection: Binding<WatermarkPosition>) -> some View {
        let fixedRows: [[WatermarkPosition]] = [
            [.tl, .tc, .tr],
            [.bl, .bc, .br]
        ]
        VStack(spacing: 8) {
            // 固定6方向（3×2グリッド）
            ForEach(fixedRows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { pos in
                        positionButton(pos, selection: selection)
                    }
                }
            }
            // 特殊モード（ランダム・タイリング）
            HStack(spacing: 8) {
                positionButton(.random, selection: selection)
                positionButton(.tile, selection: selection)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func positionButton(_ pos: WatermarkPosition,
                                 selection: Binding<WatermarkPosition>) -> some View {
        Button {
            selection.wrappedValue = pos
        } label: {
            VStack(spacing: 4) {
                Image(systemName: pos.systemImage)
                    .font(.system(size: 16))
                Text(pos.localizedLabel)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(selection.wrappedValue == pos ? .white : .primary)
            .background(
                selection.wrappedValue == pos
                    ? Color.accentColor
                    : Color.secondary.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - W3C 16色パレット

    private static let w3cColors: [(hex: String, name: String)] = [
        ("#FFFFFF", "white"),  ("#C0C0C0", "silver"), ("#808080", "gray"),  ("#000000", "black"),
        ("#FF0000", "red"),    ("#800000", "maroon"), ("#FFFF00", "yellow"),("#808000", "olive"),
        ("#00FF00", "lime"),   ("#008000", "green"),  ("#00FFFF", "aqua"),  ("#008080", "teal"),
        ("#0000FF", "blue"),   ("#000080", "navy"),   ("#FF00FF", "fuchsia"),("#800080","purple"),
    ]

    @ViewBuilder
    private func colorPalette(selection: Binding<String>) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Self.w3cColors, id: \.hex) { item in
                Button {
                    selection.wrappedValue = item.hex
                } label: {
                    Circle()
                        .fill(Color(hex: item.hex) ?? .white)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .stroke(
                                    selection.wrappedValue.uppercased() == item.hex
                                        ? Color.accentColor : Color.secondary.opacity(0.3),
                                    lineWidth: selection.wrappedValue.uppercased() == item.hex ? 2.5 : 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.name)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Color hex initializer

private extension Color {
    init?(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let n = UInt64(h, radix: 16) else { return nil }
        let r = Double((n >> 16) & 0xFF) / 255.0
        let g = Double((n >> 8) & 0xFF) / 255.0
        let b = Double(n & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
