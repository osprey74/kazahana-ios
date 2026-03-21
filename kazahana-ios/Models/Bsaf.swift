// Bsaf.swift
// kazahana-ios
// BSAF (Bluesky Structured Alert Feed) モデル定義

import Foundation

// MARK: - Bot Definition JSON Schema

struct BsafBotDefinition: Codable, Equatable {
    let bsafSchema: String
    let updatedAt: String
    let selfUrl: String
    let bot: BsafBotInfo
    let filters: [BsafFilter]

    enum CodingKeys: String, CodingKey {
        case bsafSchema = "bsaf_schema"
        case updatedAt = "updated_at"
        case selfUrl = "self_url"
        case bot, filters
    }
}

struct BsafBotInfo: Codable, Equatable {
    let handle: String
    let did: String
    let name: String
    let description: String
    let source: String
    let sourceUrl: String?

    enum CodingKeys: String, CodingKey {
        case handle, did, name, description, source
        case sourceUrl = "source_url"
    }
}

struct BsafFilter: Codable, Equatable {
    let tag: String
    let label: String
    let options: [BsafFilterOption]
}

struct BsafFilterOption: Codable, Equatable {
    let value: String
    let label: String
}

// MARK: - 登録済み Bot（永続化対象）

struct BsafRegisteredBot: Codable, Identifiable, Equatable {
    let definition: BsafBotDefinition
    /// key = filter.tag, value = ユーザーが有効にした option values
    var filterSettings: [String: [String]]
    let registeredAt: String
    var lastCheckedAt: String

    var id: String { definition.bot.did }
}

// MARK: - パース済み BSAF タグ

struct BsafParsedTags: Equatable {
    let version: String
    let type: String
    let value: String
    let time: String
    let target: String
    let source: String
}

// MARK: - 重複投稿情報

struct BsafDuplicateInfo {
    let duplicateUris: [String]
    let duplicateHandles: [String]
}

// MARK: - エラー

enum BsafError: LocalizedError {
    case invalidUrl
    case fetchFailed
    case invalidJson
    case duplicateBot

    var errorDescription: String? {
        switch self {
        case .invalidUrl:   return String(localized: "bsaf.invalidUrl")
        case .fetchFailed:  return String(localized: "bsaf.fetchFailed")
        case .invalidJson:  return String(localized: "bsaf.invalidJson")
        case .duplicateBot: return String(localized: "bsaf.duplicateBot")
        }
    }
}
