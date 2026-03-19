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
            case .system: return String(localized: "theme.system")
            case .light: return String(localized: "theme.light")
            case .dark: return String(localized: "theme.dark")
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

    // MARK: - 投稿言語設定

    /// 投稿に付与する言語（デスクトップ版と同じ11言語 + システム連動）
    enum PostLanguage: String, CaseIterable {
        case system   = "system"
        case japanese = "ja"
        case english  = "en"
        case portuguese = "pt"
        case german   = "de"
        case chineseTW = "zh-TW"
        case chineseCN = "zh-CN"
        case french   = "fr"
        case korean   = "ko"
        case spanish  = "es"
        case russian  = "ru"
        case indonesian = "id"

        /// 設定画面に表示する名前（その言語のネイティブ表記）
        var displayName: String {
            switch self {
            case .system:      return String(localized: "lang.system")
            case .japanese:    return String(localized: "lang.ja")
            case .english:     return String(localized: "lang.en")
            case .portuguese:  return String(localized: "lang.pt")
            case .german:      return String(localized: "lang.de")
            case .chineseTW:   return String(localized: "lang.zhTW")
            case .chineseCN:   return String(localized: "lang.zhCN")
            case .french:      return String(localized: "lang.fr")
            case .korean:      return String(localized: "lang.ko")
            case .spanish:     return String(localized: "lang.es")
            case .russian:     return String(localized: "lang.ru")
            case .indonesian:  return String(localized: "lang.id")
            }
        }

        /// 投稿レコードの `langs` に渡す BCP-47 コード（system の場合は nil → 呼び出し側で端末ロケール使用）
        var langCode: String? {
            self == .system ? nil : rawValue
        }
    }

    /// ユーザーが設定した投稿言語（system = 端末ロケール自動）
    var postLanguageSetting: PostLanguage {
        didSet {
            UserDefaults.standard.set(postLanguageSetting.rawValue, forKey: "postLanguageSetting")
            // AppleLanguages を書き込むことで次回起動時の表示言語を変更する
            if let code = postLanguageSetting.langCode {
                UserDefaults.standard.set([code], forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            }
        }
    }

    /// Bluesky アカウントプリファレンスから取得した言語設定（ログイン時に上書き）
    var postLanguages: [String] = []

    /// 実際に投稿レコードに渡す言語コード配列。
    /// 優先順: ユーザー設定 > Bluesky プリファレンス > 端末ロケール
    var resolvedPostLangs: [String] {
        if let code = postLanguageSetting.langCode {
            return [code]
        }
        if !postLanguages.isEmpty {
            return postLanguages
        }
        let locale = Locale.current.language.languageCode?.identifier ?? "ja"
        return [locale]
    }

    // MARK: - モデレーション設定

    /// ラベルごとのモデレーション挙動
    enum ModerationBehavior: String, CaseIterable {
        case hide = "hide"      // 非表示（タイムラインから除外）
        case warn = "warn"      // 警告（ブラー表示）
        case ignore = "ignore"  // 無視（そのまま表示）

        var displayName: String {
            switch self {
            case .hide: return String(localized: "settings.pref.hide")
            case .warn: return String(localized: "settings.pref.warn")
            case .ignore: return String(localized: "settings.pref.ignore")
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

    // MARK: - Claude API 設定

    /// Anthropic Claude API キー（ALT テキスト自動生成に使用）
    var claudeApiKey: String {
        didSet { UserDefaults.standard.set(claudeApiKey, forKey: "claudeApiKey") }
    }

    // MARK: - Init

    init() {
        let themeRaw = UserDefaults.standard.string(forKey: "theme") ?? Theme.system.rawValue
        self.theme = Theme(rawValue: themeRaw) ?? .system
        self.showVia = UserDefaults.standard.object(forKey: "showVia") as? Bool ?? false
        self.adultContentEnabled = UserDefaults.standard.object(forKey: "adultContentEnabled") as? Bool ?? false
        self.claudeApiKey = UserDefaults.standard.string(forKey: "claudeApiKey") ?? ""
        let langRaw = UserDefaults.standard.string(forKey: "postLanguageSetting") ?? PostLanguage.system.rawValue
        self.postLanguageSetting = PostLanguage(rawValue: langRaw) ?? .system
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
