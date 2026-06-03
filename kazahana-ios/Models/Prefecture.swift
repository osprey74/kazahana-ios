// Prefecture.swift
// kazahana-ios
// 都道府県コード定義（BSAF target 突き合わせ用）

import Foundation

enum Prefecture: String, CaseIterable, Codable {
    case hokkaido  = "jp-hokkaido"
    case aomori    = "jp-aomori"
    case iwate     = "jp-iwate"
    case miyagi    = "jp-miyagi"
    case akita     = "jp-akita"
    case yamagata  = "jp-yamagata"
    case fukushima = "jp-fukushima"
    case ibaraki   = "jp-ibaraki"
    case tochigi   = "jp-tochigi"
    case gunma     = "jp-gunma"
    case saitama   = "jp-saitama"
    case chiba     = "jp-chiba"
    case tokyo     = "jp-tokyo"
    case kanagawa  = "jp-kanagawa"
    case niigata   = "jp-niigata"
    case toyama    = "jp-toyama"
    case ishikawa  = "jp-ishikawa"
    case fukui     = "jp-fukui"
    case yamanashi = "jp-yamanashi"
    case nagano    = "jp-nagano"
    case gifu      = "jp-gifu"
    case shizuoka  = "jp-shizuoka"
    case aichi     = "jp-aichi"
    case mie       = "jp-mie"
    case shiga     = "jp-shiga"
    case kyoto     = "jp-kyoto"
    case osaka     = "jp-osaka"
    case hyogo     = "jp-hyogo"
    case nara      = "jp-nara"
    case wakayama  = "jp-wakayama"
    case tottori   = "jp-tottori"
    case shimane   = "jp-shimane"
    case okayama   = "jp-okayama"
    case hiroshima = "jp-hiroshima"
    case yamaguchi = "jp-yamaguchi"
    case tokushima = "jp-tokushima"
    case kagawa    = "jp-kagawa"
    case ehime     = "jp-ehime"
    case kochi     = "jp-kochi"
    case fukuoka   = "jp-fukuoka"
    case saga      = "jp-saga"
    case nagasaki  = "jp-nagasaki"
    case kumamoto  = "jp-kumamoto"
    case oita      = "jp-oita"
    case miyazaki  = "jp-miyazaki"
    case kagoshima = "jp-kagoshima"
    case okinawa   = "jp-okinawa"

    /// 日本語表示名
    var displayName: String {
        switch self {
        case .hokkaido:  return "北海道"
        case .aomori:    return "青森県"
        case .iwate:     return "岩手県"
        case .miyagi:    return "宮城県"
        case .akita:     return "秋田県"
        case .yamagata:  return "山形県"
        case .fukushima: return "福島県"
        case .ibaraki:   return "茨城県"
        case .tochigi:   return "栃木県"
        case .gunma:     return "群馬県"
        case .saitama:   return "埼玉県"
        case .chiba:     return "千葉県"
        case .tokyo:     return "東京都"
        case .kanagawa:  return "神奈川県"
        case .niigata:   return "新潟県"
        case .toyama:    return "富山県"
        case .ishikawa:  return "石川県"
        case .fukui:     return "福井県"
        case .yamanashi: return "山梨県"
        case .nagano:    return "長野県"
        case .gifu:      return "岐阜県"
        case .shizuoka:  return "静岡県"
        case .aichi:     return "愛知県"
        case .mie:       return "三重県"
        case .shiga:     return "滋賀県"
        case .kyoto:     return "京都府"
        case .osaka:     return "大阪府"
        case .hyogo:     return "兵庫県"
        case .nara:      return "奈良県"
        case .wakayama:  return "和歌山県"
        case .tottori:   return "鳥取県"
        case .shimane:   return "島根県"
        case .okayama:   return "岡山県"
        case .hiroshima: return "広島県"
        case .yamaguchi: return "山口県"
        case .tokushima: return "徳島県"
        case .kagawa:    return "香川県"
        case .ehime:     return "愛媛県"
        case .kochi:     return "高知県"
        case .fukuoka:   return "福岡県"
        case .saga:      return "佐賀県"
        case .nagasaki:  return "長崎県"
        case .kumamoto:  return "熊本県"
        case .oita:      return "大分県"
        case .miyazaki:  return "宮崎県"
        case .kagoshima: return "鹿児島県"
        case .okinawa:   return "沖縄県"
        }
    }

    /// CLGeocoder の administrativeArea（日本語名）から Prefecture を逆引き
    static func from(japaneseName: String) -> Prefecture? {
        // "東京都" → .tokyo, "北海道" → .hokkaido, "大阪府" → .osaka 等
        allCases.first { $0.displayName == japaneseName }
    }

    /// 都道府県名から検索（部分一致: "東京" → .tokyo）
    static func from(partialName: String) -> Prefecture? {
        allCases.first { $0.displayName.hasPrefix(partialName) || partialName.hasPrefix($0.displayName) }
    }
}
