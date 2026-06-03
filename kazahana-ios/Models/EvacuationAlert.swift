// EvacuationAlert.swift
// kazahana-ios
// 避難誘導 警報状態モデル（バナー制御用）

import Foundation

enum AlertLevel: String, Codable, Comparable {
    case level3 = "level3"
    case level4 = "level4"
    case level5 = "level5"

    static func < (lhs: AlertLevel, rhs: AlertLevel) -> Bool {
        let order: [AlertLevel] = [.level3, .level4, .level5]
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }

    /// バナー表示用の色（hex）
    var bannerColorHex: UInt {
        switch self {
        case .level3: return 0xCA8A04  // 黄系（警報級）
        case .level4: return 0xDC2626  // 赤系（危険）
        case .level5: return 0xBE185D  // ピンク系（特別警報級）
        }
    }
}

struct ActiveAlert: Codable, Identifiable, Equatable {
    let type: String            // BSAF type（heavy-rain-warning など）
    let value: AlertLevel       // BSAF value
    let time: String            // BSAF time（ISO8601, dedupe key の一部）
    let target: String          // BSAF target（jp-xxxx）
    let receivedAt: Date        // 受信時刻（タイムアウト判定用）

    /// 重複排除キー（type + value + time + target の完全一致）
    var id: String { "\(type)|\(value.rawValue)|\(time)|\(target)" }
}
