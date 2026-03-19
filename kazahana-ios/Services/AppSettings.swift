// AppSettings.swift
// kazahana-ios
// アプリ設定の永続化（UserDefaults）

import SwiftUI
import Observation

@Observable
final class AppSettings {

    // MARK: - テーマ設定

    enum Theme: String, CaseIterable {
        case system = "system"
        case light = "light"
        case dark = "dark"

        var displayName: String {
            switch self {
            case .system: return "システム連動"
            case .light: return "ライト"
            case .dark: return "ダーク"
            }
        }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    // MARK: - 設定値

    var theme: Theme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
    }

    /// 投稿元（via）をレコードに付与するか
    var showVia: Bool {
        didSet { UserDefaults.standard.set(showVia, forKey: "showVia") }
    }

    /// via として付与するクライアント名
    let viaName: String = "kazahana for iOS"

    /// Bluesky プリファレンスから取得した投稿言語設定（空の場合は端末ロケールを使用）
    var postLanguages: [String] = []

    // MARK: - モデレーション設定

    /// ラベルごとのモデレーション挙動
    enum ModerationBehavior: String, CaseIterable {
        case hide = "hide"      // 非表示（タイムラインから除外）
        case warn = "warn"      // 警告（ブラー表示）
        case ignore = "ignore"  // 無視（そのまま表示）

        var displayName: String {
            switch self {
            case .hide: return "非表示"
            case .warn: return "警告"
            case .ignore: return "表示"
            }
        }
    }

    /// 成人向けコンテンツの表示を許可するか（false = 全て非表示）
    var adultContentEnabled: Bool {
        didSet { UserDefaults.standard.set(adultContentEnabled, forKey: "adultContentEnabled") }
    }

    /// ラベル値ごとの表示設定（キー: ラベル値、値: ModerationBehavior）
    var labelPreferences: [String: ModerationBehavior] {
        didSet {
            let encoded = labelPreferences.mapValues { $0.rawValue }
            UserDefaults.standard.set(encoded, forKey: "labelPreferences")
        }
    }

    // MARK: - Init

    init() {
        let themeRaw = UserDefaults.standard.string(forKey: "theme") ?? Theme.system.rawValue
        self.theme = Theme(rawValue: themeRaw) ?? .system
        self.showVia = UserDefaults.standard.object(forKey: "showVia") as? Bool ?? false
        self.adultContentEnabled = UserDefaults.standard.object(forKey: "adultContentEnabled") as? Bool ?? false
        if let stored = UserDefaults.standard.dictionary(forKey: "labelPreferences") as? [String: String] {
            self.labelPreferences = stored.compactMapValues { ModerationBehavior(rawValue: $0) }
        } else {
            self.labelPreferences = [
                "porn": .hide,
                "sexual": .warn,
                "graphic-media": .warn,
                "nudity": .warn,
                "gore": .warn,
            ]
        }
    }

    // MARK: - Singleton

    static let shared = AppSettings()
}
