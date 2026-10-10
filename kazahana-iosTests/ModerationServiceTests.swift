//
//  ModerationServiceTests.swift
//  kazahana-iosTests
//

import Foundation
import Testing
@testable import kazahana

/// AppSettings は App Group の UserDefaults に書き込むため、
/// 各テストで変更した設定を元に戻し、並列実行もしない
@MainActor
@Suite(.serialized)
struct ModerationServiceTests {

    private func withSettings(
        adultContentEnabled: Bool,
        preferences: [String: AppSettings.ModerationBehavior] = [:],
        _ body: (ModerationService) throws -> Void
    ) rethrows {
        let settings = AppSettings()
        let savedAdult = settings.adultContentEnabled
        let savedPreferences = settings.labelPreferences
        defer {
            settings.adultContentEnabled = savedAdult
            settings.labelPreferences = savedPreferences
        }
        settings.adultContentEnabled = adultContentEnabled
        settings.labelPreferences = preferences
        try body(ModerationService(settings: settings))
    }

    private func labels(_ values: String...) -> [ContentLabel] {
        values.map { try! decode(ContentLabel.self, #"{ "val": "\#($0)" }"#) }
    }

    @Test func ラベルがなければ通常表示() {
        withSettings(adultContentEnabled: false) { service in
            #expect(service.moderateAuthor(labels: nil) == .none)
            #expect(service.moderateAuthor(labels: []) == .none)
        }
    }

    @Test func システムラベルは設定に関わらず固定() {
        withSettings(adultContentEnabled: true) { service in
            #expect(service.moderateAuthor(labels: labels("!hide")).decision == .filter)
            #expect(service.moderateAuthor(labels: labels("!warn")).decision == .blur)
            #expect(service.moderateAuthor(labels: labels("!no-unauthenticated")).decision == .none)
            #expect(service.moderateAuthor(labels: labels("unknown-label")).decision == .none)
        }
    }

    @Test func 打ち消しラベルは無視する() throws {
        let negated = try decode(ContentLabel.self, #"{ "val": "!hide", "neg": true }"#)
        withSettings(adultContentEnabled: true) { service in
            #expect(service.moderateAuthor(labels: [negated]) == .none)
        }
    }

    @Test(arguments: ["porn", "sexual", "nudity"])
    func 成人向けが無効なら成人向けラベルは非表示(label: String) {
        withSettings(adultContentEnabled: false, preferences: [label: .ignore]) { service in
            #expect(service.moderateAuthor(labels: labels(label)).decision == .filter)
        }
    }

    @Test func 成人向けが無効でもグラフィックは設定に従う() {
        withSettings(adultContentEnabled: false, preferences: ["gore": .ignore]) { service in
            #expect(service.moderateAuthor(labels: labels("gore")).decision == .none)
        }
    }

    @Test(arguments: [
        (AppSettings.ModerationBehavior.hide, ModerationDecision.filter),
        (.warn, .mediaBlur),
        (.ignore, .none),
    ])
    func 成人向けが有効なら設定に従う(behavior: AppSettings.ModerationBehavior, expected: ModerationDecision) {
        withSettings(adultContentEnabled: true, preferences: ["sexual": behavior]) { service in
            #expect(service.moderateAuthor(labels: labels("sexual")).decision == expected)
        }
    }

    @Test func 設定がなければ警告にする() {
        withSettings(adultContentEnabled: true, preferences: [:]) { service in
            let result = service.moderateAuthor(labels: labels("graphic-media"))
            #expect(result.decision == .mediaBlur)
            #expect(result.message != nil)
        }
    }

    @Test func 投稿と著者のラベルのうち最も厳しい判定を使う() throws {
        let post = try decode(PostView.self, postViewJSON(
            labels: #"[{ "val": "gore" }]"#,
            authorLabels: #"[{ "val": "!hide" }]"#
        ))
        withSettings(adultContentEnabled: true, preferences: ["gore": .warn]) { service in
            #expect(service.moderatePost(post).decision == .filter)
        }
    }
}
