// Shelter.swift
// kazahana-ios
// 避難所データモデル（国土地理院 指定緊急避難場所・指定避難所データ）

import Foundation

struct Shelter: Codable, Identifiable {
    let id: String              // 共通ID（国土地理院）
    let name: String            // 施設・場所名
    let lat: Double             // 緯度
    let lng: Double             // 経度
    let prefecture: String      // 都道府県（jp-xxxx 形式）
    let hazards: ShelterHazards // 対応災害種別フラグ
}

struct ShelterHazards: Codable {
    let flood: Bool             // 洪水
    let landslide: Bool         // 崖崩れ・土石流・地滑り
    let stormSurge: Bool        // 高潮
    let earthquake: Bool        // 地震
    let tsunami: Bool           // 津波
    let fire: Bool              // 大規模な火事
    let inlandFlood: Bool       // 内水氾濫
    let volcano: Bool           // 火山現象
}

struct ShelterWithDistance: Identifiable {
    let shelter: Shelter
    let distance: Double  // メートル

    var id: String { shelter.id }

    /// 距離の表示用フォーマット
    var formattedDistance: String {
        if distance >= 1000 {
            return String(format: "%.1f km", distance / 1000)
        }
        return String(format: "%.0f m", distance)
    }
}
