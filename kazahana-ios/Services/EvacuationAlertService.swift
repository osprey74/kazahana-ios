// EvacuationAlertService.swift
// kazahana-ios
// 避難誘導トリガー判定・BSAF type → 災害種別マッピング

import Foundation

struct EvacuationAlertService {

    /// 避難レベルの value セット
    private static let alertValues: Set<String> = ["level3", "level4", "level5"]

    // MARK: - トリガー判定

    /// BSAF パース済みタグが避難誘導トリガーか判定
    static func isEvacuationTrigger(_ parsed: BsafParsedTags, prefecture: String) -> Bool {
        parsed.target == prefecture && alertValues.contains(parsed.value)
    }

    /// value 文字列を AlertLevel に変換
    static func toAlertLevel(_ value: String) -> AlertLevel? {
        AlertLevel(rawValue: value)
    }

    // MARK: - BSAF type → 災害種別マッピング

    /// BSAF type から対応する災害種別 KeyPath を導出（OR 条件で適用）
    /// 1つの type が複数の災害種別に対応する場合がある（例: 大雨 → 洪水+土砂+内水氾濫）
    ///
    /// NOTE: マッピングは bsaf-kikikuru-bot の実際の type 値を確認して確定すること。
    /// 未知の type に対しては全種別を候補にする（安全側倒し）。
    static func hazardFilters(for bsafType: String) -> [KeyPath<ShelterHazards, Bool>] {
        switch bsafType {
        // 大雨系
        case "heavy-rain-warning", "heavy-rain":
            return [\.flood, \.landslide, \.inlandFlood]
        // 洪水系
        case "flood-warning", "flood":
            return [\.flood, \.inlandFlood]
        // 土砂災害系
        case "landslide-warning", "landslide":
            return [\.landslide]
        // 高潮系
        case "storm-surge-warning", "storm-surge":
            return [\.stormSurge]
        // 津波系
        case "tsunami-warning", "tsunami":
            return [\.tsunami]
        // 地震系
        case "earthquake-warning", "earthquake":
            return [\.earthquake]
        // 火山系
        case "volcanic-warning", "volcanic":
            return [\.volcano]
        // 暴風系（建物被害メイン。避難所は地震対応が近い）
        case "storm-warning", "storm":
            return [\.flood, \.landslide]
        default:
            // 未知の type → 全種別を候補にする（安全側倒し）
            return [\.flood, \.landslide, \.stormSurge, \.earthquake,
                    \.tsunami, \.fire, \.inlandFlood, \.volcano]
        }
    }
}
