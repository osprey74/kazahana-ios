// WatermarkSettings.swift
// kazahana-ios
// ウォーターマーク設定モデル

import Foundation

enum WatermarkPreset: String, CaseIterable, Codable {
    case copyright, ai_ja, ai_en, ai_both, photo, custom

    var localizedLabel: String {
        switch self {
        case .copyright: return String(localized: "watermark.presetCopyright")
        case .ai_ja:     return String(localized: "watermark.presetAiJa")
        case .ai_en:     return String(localized: "watermark.presetAiEn")
        case .ai_both:   return String(localized: "watermark.presetAiBoth")
        case .photo:     return String(localized: "watermark.presetPhoto")
        case .custom:    return String(localized: "watermark.presetCustom")
        }
    }
}

enum WatermarkPosition: String, CaseIterable, Codable {
    case tl, tc, tr, bl, bc, br

    var localizedLabel: String {
        switch self {
        case .tl: return String(localized: "watermark.posTopLeft")
        case .tc: return String(localized: "watermark.posTopCenter")
        case .tr: return String(localized: "watermark.posTopRight")
        case .bl: return String(localized: "watermark.posBottomLeft")
        case .bc: return String(localized: "watermark.posBottomCenter")
        case .br: return String(localized: "watermark.posBottomRight")
        }
    }

    var systemImage: String {
        switch self {
        case .tl: return "arrow.up.left"
        case .tc: return "arrow.up"
        case .tr: return "arrow.up.right"
        case .bl: return "arrow.down.left"
        case .bc: return "arrow.down"
        case .br: return "arrow.down.right"
        }
    }
}

struct WatermarkSettings: Codable, Equatable {
    var enabled: Bool = false
    var preset: WatermarkPreset = .copyright
    var customText: String = ""
    var position: WatermarkPosition = .br
    var opacity: Double = 70       // 20–100
    var fontSize: Double = 12      // 8–20
    var textColor: String = "#FFFFFF"
    var skipVideo: Bool = true
    var confirmBeforePost: Bool = true

    static let defaultsKey = "watermarkSettings"

    static func load() -> WatermarkSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(WatermarkSettings.self, from: data)
        else { return WatermarkSettings() }
        return settings
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: WatermarkSettings.defaultsKey)
    }
}
