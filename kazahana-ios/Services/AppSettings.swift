// AppSettings.swift
// kazahana-ios
// アプリ設定の永続化（UserDefaults）

import SwiftUI
import Observation

@Observable
final class AppSettings {

    // MARK: - App Group UserDefaults

    /// メインアプリと Share Extension で設定を共有するための UserDefaults
    static let suiteName = "group.com.osprey74.kazahana-ios"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }
    private var defaults: UserDefaults { AppSettings.defaults }

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

    // MARK: - ポーリング間隔設定

    /// タイムライン自動更新の間隔（秒）
    enum PollingInterval: Int, CaseIterable {
        case never  = 0
        case sec30  = 30
        case sec60  = 60
        case sec90  = 90
        case sec120 = 120

        var displayName: String {
            switch self {
            case .never:  return String(localized: "settings.polling.never")
            case .sec30:  return String(localized: "settings.polling.30s")
            case .sec60:  return String(localized: "settings.polling.60s")
            case .sec90:  return String(localized: "settings.polling.90s")
            case .sec120: return String(localized: "settings.polling.120s")
            }
        }
    }

    // MARK: - 設定値

    var theme: Theme {
        didSet { defaults.set(theme.rawValue, forKey: "theme") }
    }

    /// タイムライン自動更新の間隔
    var timelinePollingInterval: PollingInterval {
        didSet { defaults.set(timelinePollingInterval.rawValue, forKey: "timelinePollingInterval") }
    }

    /// 投稿元（via）をレコードに付与するか
    var showVia: Bool {
        didSet { defaults.set(showVia, forKey: "showVia") }
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
            defaults.set(postLanguageSetting.rawValue, forKey: "postLanguageSetting")
            // AppleLanguages を書き込むことで次回起動時の表示言語を変更する
            if let code = postLanguageSetting.langCode {
                defaults.set([code], forKey: "AppleLanguages")
            } else {
                defaults.removeObject(forKey: "AppleLanguages")
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
        didSet { defaults.set(adultContentEnabled, forKey: "adultContentEnabled") }
    }

    /// ラベル値ごとの表示設定（キー: ラベル値、値: ModerationBehavior）
    var labelPreferences: [String: ModerationBehavior] {
        didSet {
            let encoded = labelPreferences.mapValues { $0.rawValue }
            defaults.set(encoded, forKey: "labelPreferences")
        }
    }

    // MARK: - Claude API 設定

    /// Anthropic Claude API キー（ALT テキスト自動生成に使用）
    var claudeApiKey: String {
        didSet { defaults.set(claudeApiKey, forKey: "claudeApiKey") }
    }

    // MARK: - ホームフィード管理設定

    /// ホームタブに表示するフィード/リストのURI順序リスト（空 = 全フィード表示）
    var pinnedFeedURIs: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(pinnedFeedURIs) {
                defaults.set(data, forKey: "pinnedFeedURIs")
            }
        }
    }

    /// 非表示にしたフィード/リストのURIリスト
    var hiddenFeedURIs: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(hiddenFeedURIs) {
                defaults.set(data, forKey: "hiddenFeedURIs")
            }
        }
    }

    /// フィード選択メニューに全フィード/リストを表示するか
    var showAllFeedsInSelector: Bool {
        didSet { defaults.set(showAllFeedsInSelector, forKey: "showAllFeedsInSelector") }
    }

    // MARK: - サポーターバッジ設定

    /// サポーターバッジの有効期限（nil = 未購入または期限切れ）
    var supporterBadgeExpiryDate: Date? {
        didSet {
            if let date = supporterBadgeExpiryDate {
                defaults.set(date.timeIntervalSince1970, forKey: "supporterBadgeExpiryDate")
            } else {
                defaults.removeObject(forKey: "supporterBadgeExpiryDate")
            }
        }
    }

    /// サポーターバッジが現在有効かどうか
    var isSupporterBadgeActive: Bool {
        guard let expiry = supporterBadgeExpiryDate else { return false }
        return expiry > Date()
    }

    // MARK: - BSAF 設定

    /// BSAF 機能の有効/無効
    var bsafEnabled: Bool {
        didSet { defaults.set(bsafEnabled, forKey: "bsafEnabled") }
    }

    /// 登録済み BSAF Bot リスト
    var bsafRegisteredBots: [BsafRegisteredBot] {
        didSet {
            if let data = try? JSONEncoder().encode(bsafRegisteredBots) {
                defaults.set(data, forKey: "bsafRegisteredBots")
            }
        }
    }

    // MARK: - Init

    init() {
        let d = AppSettings.defaults
        let themeRaw = d.string(forKey: "theme") ?? Theme.system.rawValue
        self.theme = Theme(rawValue: themeRaw) ?? .system
        let pollingRaw = d.integer(forKey: "timelinePollingInterval")
        self.timelinePollingInterval = PollingInterval(rawValue: pollingRaw) ?? .sec60
        self.showVia = d.object(forKey: "showVia") as? Bool ?? false
        self.adultContentEnabled = d.object(forKey: "adultContentEnabled") as? Bool ?? false
        self.claudeApiKey = d.string(forKey: "claudeApiKey") ?? ""
        let langRaw = d.string(forKey: "postLanguageSetting") ?? PostLanguage.system.rawValue
        self.postLanguageSetting = PostLanguage(rawValue: langRaw) ?? .system
        if let stored = d.dictionary(forKey: "labelPreferences") as? [String: String] {
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
        if let data = d.data(forKey: "pinnedFeedURIs"),
           let uris = try? JSONDecoder().decode([String].self, from: data) {
            self.pinnedFeedURIs = uris
        } else {
            self.pinnedFeedURIs = []
        }
        if let data = d.data(forKey: "hiddenFeedURIs"),
           let uris = try? JSONDecoder().decode([String].self, from: data) {
            self.hiddenFeedURIs = uris
        } else {
            self.hiddenFeedURIs = []
        }
        self.showAllFeedsInSelector = d.object(forKey: "showAllFeedsInSelector") as? Bool ?? true
        let badgeInterval = d.double(forKey: "supporterBadgeExpiryDate")
        self.supporterBadgeExpiryDate = badgeInterval > 0 ? Date(timeIntervalSince1970: badgeInterval) : nil
        self.bsafEnabled = d.object(forKey: "bsafEnabled") as? Bool ?? false
        if let data = d.data(forKey: "bsafRegisteredBots"),
           let bots = try? JSONDecoder().decode([BsafRegisteredBot].self, from: data) {
            self.bsafRegisteredBots = bots
        } else {
            self.bsafRegisteredBots = []
        }
    }

    // MARK: - BSAF Bot 管理

    /// 新しい BSAF Bot を登録する。全フィルタオプションを有効で初期化する。
    func registerBot(_ definition: BsafBotDefinition) {
        var filterSettings: [String: [String]] = [:]
        for filter in definition.filters {
            filterSettings[filter.tag] = filter.options.map { $0.value }
        }
        let formatter = ISO8601DateFormatter()
        let now = formatter.string(from: Date())
        let bot = BsafRegisteredBot(
            definition: definition,
            filterSettings: filterSettings,
            registeredAt: now,
            lastCheckedAt: now
        )
        bsafRegisteredBots.append(bot)
    }

    /// BSAF Bot を DID で検索して登録解除する。
    func unregisterBot(did: String) {
        bsafRegisteredBots.removeAll { $0.definition.bot.did == did }
    }

    /// 特定 Bot の特定フィルタタグの有効値を更新する。
    func setFilterOptions(did: String, tag: String, values: [String]) {
        guard let index = bsafRegisteredBots.firstIndex(where: { $0.definition.bot.did == did }) else { return }
        bsafRegisteredBots[index].filterSettings[tag] = values
    }

    /// 投稿著者の DID から登録済み Bot を検索する。
    func findRegisteredBot(did: String) -> BsafRegisteredBot? {
        bsafRegisteredBots.first { $0.definition.bot.did == did }
    }

    // MARK: - Singleton

    static let shared = AppSettings()
}
