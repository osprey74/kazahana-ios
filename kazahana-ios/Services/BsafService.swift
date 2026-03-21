// BsafService.swift
// kazahana-ios
// BSAF コアロジック（パース・フィルタ・重複検出・Bot定義取得・自動更新）
// デスクトップ版 src/lib/bsaf.ts + src/lib/bsafUpdater.ts の Swift 移植

import Foundation
import SwiftUI

// MARK: - BSAF サービス

struct BsafService {

    // MARK: - タグパース

    /// BSAF タグを投稿の tags 配列からパースする。
    /// "bsaf:v1" が含まれない場合は nil を返す。
    static func parseBsafTags(_ tags: [String]) -> BsafParsedTags? {
        guard tags.contains("bsaf:v1") else { return nil }

        var type: String?
        var value: String?
        var time: String?
        var target: String?
        var source: String?

        for tag in tags {
            guard let colonRange = tag.range(of: ":") else { continue }
            let key = String(tag[tag.startIndex..<colonRange.lowerBound])
            let val = String(tag[colonRange.upperBound...])

            switch key {
            case "type":   type = val
            case "value":  value = val
            case "time":   time = val
            case "target": target = val
            case "source": source = val
            default: break
            }
        }

        guard let type, let value, let time, let target, let source else {
            return nil
        }
        return BsafParsedTags(
            version: "v1", type: type, value: value,
            time: time, target: target, source: source
        )
    }

    // MARK: - フィルタロジック

    /// BSAF 投稿を表示すべきかを判定する（AND 条件）。
    /// 各フィルタタグについて、投稿の値がユーザーの有効セットに含まれるかをチェックする。
    static func shouldShowBsafPost(_ parsed: BsafParsedTags, bot: BsafRegisteredBot) -> Bool {
        for filter in bot.definition.filters {
            guard let enabledValues = bot.filterSettings[filter.tag] else { continue }

            // フィルタタグに対応するパース済みフィールドを取得
            let postValue: String?
            switch filter.tag {
            case "type":   postValue = parsed.type
            case "value":  postValue = parsed.value
            case "time":   postValue = parsed.time
            case "target": postValue = parsed.target
            case "source": postValue = parsed.source
            default:       postValue = nil
            }

            guard let postValue else { continue }
            if !enabledValues.contains(postValue) { return false }
        }
        return true
    }

    // MARK: - 重複検出

    /// 重複グループのキーを生成する（type|value|time|target）
    static func duplicateKey(_ parsed: BsafParsedTags) -> String {
        "\(parsed.type)|\(parsed.value)|\(parsed.time)|\(parsed.target)"
    }

    // MARK: - 深刻度カラー

    private static let earthquakeIntensities: Set<String> = [
        "1", "2", "3", "4", "5-", "5+", "6-", "6+", "7"
    ]

    /// BSAF value から深刻度ボーダーカラーを取得する。
    /// 震度: 高→ピンク/赤/オレンジ/緑。気象: 特別警報→ピンク、警報→オレンジ、注意報→黄、その他→青。
    static func severityBorderColor(for value: String) -> Color {
        if earthquakeIntensities.contains(value) {
            if ["6-", "6+", "7"].contains(value) { return Color(hex: 0xBE185D) }
            if ["5-", "5+"].contains(value)       { return Color(hex: 0xDC2626) }
            if value == "4"                        { return Color(hex: 0xD97706) }
            return Color(hex: 0x16A34A)
        }
        switch value {
        case "special-warning":           return Color(hex: 0xBE185D)
        case "severe-warning", "warning": return Color(hex: 0xD97706)
        case "advisory":                  return Color(hex: 0xCA8A04)
        default:                          return Color(hex: 0x2563EB)
        }
    }

    // MARK: - GitHub URL 変換

    /// GitHub blob/tree URL を raw content URL に変換する。
    static func toRawUrl(_ url: String) -> String {
        let pattern = #"^https?://github\.com/([^/]+)/([^/]+)/blob/(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
              let userRange = Range(match.range(at: 1), in: url),
              let repoRange = Range(match.range(at: 2), in: url),
              let pathRange = Range(match.range(at: 3), in: url)
        else { return url }
        let user = String(url[userRange])
        let repo = String(url[repoRange])
        let path = String(url[pathRange])
        return "https://raw.githubusercontent.com/\(user)/\(repo)/\(path)"
    }

    // MARK: - Bot定義取得

    /// URL から Bot Definition JSON を取得してバリデーションする。
    /// GitHub blob URL は自動的に raw URL へ変換する。
    static func fetchBotDefinition(from urlString: String) async throws -> BsafBotDefinition {
        let rawUrlString = toRawUrl(urlString)
        guard let url = URL(string: rawUrlString) else {
            throw BsafError.invalidUrl
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw BsafError.fetchFailed
        }
        do {
            let definition = try JSONDecoder().decode(BsafBotDefinition.self, from: data)
            return definition
        } catch {
            throw BsafError.invalidJson
        }
    }

    // MARK: - Bot定義自動更新

    /// アプリ起動時に登録済み Bot の定義を一括チェックし、更新があれば適用する。
    /// フィルタ設定は既存値を保持しつつ、新しいオプションを有効で追加する。
    static func checkBotUpdates(settings: AppSettings) async {
        let bots = settings.bsafRegisteredBots
        guard !bots.isEmpty else { return }

        var updatedBots = bots
        var changed = false
        let formatter = ISO8601DateFormatter()

        for (index, bot) in bots.enumerated() {
            let selfUrl = bot.definition.selfUrl
            guard !selfUrl.isEmpty else { continue }

            do {
                let newDef = try await fetchBotDefinition(from: selfUrl)
                let now = formatter.string(from: Date())
                updatedBots[index].lastCheckedAt = now
                changed = true

                if newDef.updatedAt != bot.definition.updatedAt {
                    // フィルタ設定をマージ: 既存の有効値を保持し、新しいオプションは有効で追加
                    var filterSettings: [String: [String]] = [:]
                    for filter in newDef.filters {
                        let existing = bot.filterSettings[filter.tag] ?? []
                        let validValues = Set(filter.options.map { $0.value })
                        let kept = existing.filter { validValues.contains($0) }
                        let newValues = filter.options.map { $0.value }
                            .filter { !existing.contains($0) && !kept.contains($0) }
                        filterSettings[filter.tag] = kept + newValues
                    }
                    updatedBots[index] = BsafRegisteredBot(
                        definition: newDef,
                        filterSettings: filterSettings,
                        registeredAt: bot.registeredAt,
                        lastCheckedAt: now
                    )
                }
            } catch {
                // 更新チェック失敗は警告のみ（登録は維持）
                print("[BSAF] Failed to check updates for \(bot.definition.bot.name): \(error)")
            }
        }

        if changed {
            await MainActor.run {
                settings.bsafRegisteredBots = updatedBots
            }
        }
    }
}

// MARK: - Color 拡張（16進数カラーコード）

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
