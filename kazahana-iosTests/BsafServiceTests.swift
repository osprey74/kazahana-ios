//
//  BsafServiceTests.swift
//  kazahana-iosTests
//

import Foundation
import Testing
@testable import kazahana

@MainActor
struct BsafParseTests {

    private let tags = [
        "bsaf:v1", "type:earthquake", "value:5+",
        "time:2026-10-10T00:00:00Z", "target:jp-tokyo", "source:jma",
    ]

    @Test func すべてのタグを読み取る() throws {
        let parsed = try #require(BsafService.parseBsafTags(tags))
        #expect(parsed == BsafParsedTags(
            version: "v1", type: "earthquake", value: "5+",
            time: "2026-10-10T00:00:00Z", target: "jp-tokyo", source: "jma"
        ))
    }

    @Test func 時刻のコロンで分割しない() throws {
        #expect(try #require(BsafService.parseBsafTags(tags)).time == "2026-10-10T00:00:00Z")
    }

    @Test func bsafv1がなければnil() {
        #expect(BsafService.parseBsafTags(tags.filter { $0 != "bsaf:v1" }) == nil)
        #expect(BsafService.parseBsafTags(["bsaf:v2"] + tags.dropFirst()) == nil)
    }

    @Test func 必須のタグが欠けていればnil() {
        #expect(BsafService.parseBsafTags(tags.filter { !$0.hasPrefix("source:") }) == nil)
    }

    @Test func 重複キーは送信元を含めない() throws {
        let parsed = try #require(BsafService.parseBsafTags(tags))
        #expect(BsafService.duplicateKey(parsed) == "earthquake|5+|2026-10-10T00:00:00Z|jp-tokyo")
    }
}

@MainActor
struct BsafFilterTests {

    private let parsed = BsafParsedTags(
        version: "v1", type: "earthquake", value: "5+",
        time: "t", target: "jp-tokyo", source: "jma"
    )

    private func bot(filterTags: [String], settings: [String: [String]]) -> BsafRegisteredBot {
        let definition = BsafBotDefinition(
            bsafSchema: "1", updatedAt: "", selfUrl: "",
            bot: BsafBotInfo(handle: "bot.example", did: "did:plc:bot", name: "Bot",
                             description: "", source: "", sourceUrl: nil),
            filters: filterTags.map { BsafFilter(tag: $0, label: $0, options: []) }
        )
        return BsafRegisteredBot(definition: definition, filterSettings: settings,
                                 registeredAt: "", lastCheckedAt: "")
    }

    @Test func すべての条件を満たせば表示する() {
        let b = bot(filterTags: ["type", "target"], settings: ["type": ["earthquake"], "target": ["jp-tokyo"]])
        #expect(BsafService.shouldShowBsafPost(parsed, bot: b))
    }

    @Test func ひとつでも外れれば表示しない() {
        let b = bot(filterTags: ["type", "target"], settings: ["type": ["earthquake"], "target": ["jp-osaka"]])
        #expect(!BsafService.shouldShowBsafPost(parsed, bot: b))
    }

    @Test func 有効な値が空なら表示しない() {
        let b = bot(filterTags: ["type"], settings: ["type": []])
        #expect(!BsafService.shouldShowBsafPost(parsed, bot: b))
    }

    @Test func 設定のないフィルタや未知のタグは無視する() {
        let b = bot(filterTags: ["type", "unknown"], settings: ["unknown": ["x"]])
        #expect(BsafService.shouldShowBsafPost(parsed, bot: b))
    }
}

@MainActor
struct BsafURLTests {

    @Test func GitHubのblobURLをrawURLに変換する() {
        #expect(BsafService.toRawUrl("https://github.com/user/repo/blob/main/bots/a.json")
                == "https://raw.githubusercontent.com/user/repo/main/bots/a.json")
    }

    @Test(arguments: [
        "https://github.com/user/repo/tree/main/bots",
        "https://raw.githubusercontent.com/user/repo/main/a.json",
        "https://example.com/a.json",
    ])
    func それ以外のURLは変換しない(url: String) {
        #expect(BsafService.toRawUrl(url) == url)
    }
}

@MainActor
struct BsafBotDefinitionTests {

    @Test func スネークケースのJSONを読み込む() throws {
        let json = """
        {
          "bsaf_schema": "1.0",
          "updated_at": "2026-10-10",
          "self_url": "https://example.com/bot.json",
          "bot": { "handle": "bot.example", "did": "did:plc:bot", "name": "Bot", "description": "d", "source": "jma" },
          "filters": [{ "tag": "type", "label": "種別", "options": [{ "value": "earthquake", "label": "地震" }] }]
        }
        """
        let definition = try decode(BsafBotDefinition.self, json)
        #expect(definition.bsafSchema == "1.0")
        #expect(definition.selfUrl == "https://example.com/bot.json")
        #expect(definition.bot.sourceUrl == nil)
        #expect(definition.filters.first?.options.first?.value == "earthquake")
    }
}

@MainActor
struct EvacuationAlertServiceTests {

    private func tags(value: String, target: String = "jp-tokyo") -> BsafParsedTags {
        BsafParsedTags(version: "v1", type: "heavy-rain-warning", value: value,
                       time: "t", target: target, source: "jma")
    }

    @Test(arguments: ["level3", "level4", "level5"])
    func 対象地域のレベル3以上は避難誘導の対象(value: String) {
        #expect(EvacuationAlertService.isEvacuationTrigger(tags(value: value), prefecture: "jp-tokyo"))
    }

    @Test func レベル2は対象外() {
        #expect(!EvacuationAlertService.isEvacuationTrigger(tags(value: "level2"), prefecture: "jp-tokyo"))
    }

    @Test func 別の地域は対象外() {
        #expect(!EvacuationAlertService.isEvacuationTrigger(tags(value: "level5", target: "jp-osaka"), prefecture: "jp-tokyo"))
    }

    @Test func 大雨は洪水と土砂と内水氾濫に対応する() {
        #expect(EvacuationAlertService.hazardFilters(for: "heavy-rain-warning")
                == [\ShelterHazards.flood, \.landslide, \.inlandFlood])
    }

    @Test func 未知の種別は全災害を候補にする() {
        #expect(EvacuationAlertService.hazardFilters(for: "something-new").count == 8)
    }

    @Test func 警報レベルは3から5の順に重くなる() {
        #expect(AlertLevel.level3 < .level4)
        #expect(AlertLevel.level4 < .level5)
        #expect(EvacuationAlertService.toAlertLevel("level4") == .level4)
        #expect(EvacuationAlertService.toAlertLevel("level9") == nil)
    }
}
