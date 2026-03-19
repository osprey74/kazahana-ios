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

    /// via として付与するクライアント名（デスクトップ版と統一）
    let viaName: String = "kazahana"

    /// Bluesky プリファレンスから取得した投稿言語設定（空の場合は端末ロケールを使用）
    var postLanguages: [String] = []

    // MARK: - Init

    init() {
        let themeRaw = UserDefaults.standard.string(forKey: "theme") ?? Theme.system.rawValue
        self.theme = Theme(rawValue: themeRaw) ?? .system
        self.showVia = UserDefaults.standard.object(forKey: "showVia") as? Bool ?? false
    }

    // MARK: - Singleton

    static let shared = AppSettings()
}
