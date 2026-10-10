//
//  ShelterServiceTests.swift
//  kazahana-iosTests
//

import CoreLocation
import Foundation
import Testing
@testable import kazahana

@MainActor
struct ShelterDistanceTests {

    @Test func 同じ地点の距離は0() {
        #expect(ShelterService.haversineDistance(lat1: 35.681, lng1: 139.767, lat2: 35.681, lng2: 139.767) == 0)
    }

    @Test func 東京駅から大阪駅は約400km() {
        let d = ShelterService.haversineDistance(lat1: 35.681, lng1: 139.767, lat2: 34.702, lng2: 135.495)
        #expect(abs(d - 403_000) < 5_000)
    }

    @Test(arguments: [
        (CLLocationCoordinate2D(latitude: 1, longitude: 0), 0.0),     // 北
        (CLLocationCoordinate2D(latitude: 0, longitude: 1), 90.0),    // 東
        (CLLocationCoordinate2D(latitude: -1, longitude: 0), 180.0),  // 南
        (CLLocationCoordinate2D(latitude: 0, longitude: -1), 270.0),  // 西
    ])
    func 方位角は真北を0度とする時計回り(to: CLLocationCoordinate2D, expected: Double) {
        let b = ShelterService.bearing(from: CLLocationCoordinate2D(latitude: 0, longitude: 0), to: to)
        #expect(abs(b - expected) < 0.001)
        #expect(b >= 0 && b < 360)
    }

    @Test(arguments: [
        (999.4, "999 m"),
        (1000.0, "1.0 km"),
        (12_345.0, "12.3 km"),
    ])
    func 距離の表示(distance: Double, expected: String) {
        let shelter = Shelter(id: "1", name: "s", lat: 0, lng: 0, prefecture: "jp-tokyo", hazards: .stub())
        #expect(ShelterWithDistance(shelter: shelter, distance: distance).formattedDistance == expected)
    }
}

@MainActor
struct ShelterSearchTests {

    private let origin = CLLocationCoordinate2D(latitude: 35.0, longitude: 139.0)

    private var index: [String: [Shelter]] {
        [
            "jp-tokyo": [
                Shelter(id: "far", name: "遠い", lat: 35.05, lng: 139.0, prefecture: "jp-tokyo", hazards: .stub(flood: true)),
                Shelter(id: "near", name: "近い", lat: 35.01, lng: 139.0, prefecture: "jp-tokyo", hazards: .stub(earthquake: true)),
                Shelter(id: "mid", name: "中間", lat: 35.02, lng: 139.0, prefecture: "jp-tokyo", hazards: .stub(flood: true, earthquake: true)),
            ],
            "jp-kanagawa": [
                Shelter(id: "other", name: "隣県", lat: 35.005, lng: 139.0, prefecture: "jp-kanagawa", hazards: .stub(flood: true)),
            ],
        ]
    }

    @Test func 近い順に並べる() {
        let result = ShelterService.findNearest(shelterIndex: index, prefecture: "jp-tokyo", from: origin,
                                                hazardFilters: [\.flood, \.earthquake])
        #expect(result.map(\.shelter.id) == ["near", "mid", "far"])
    }

    @Test func 災害種別はいずれかに対応すれば候補にする() {
        let result = ShelterService.findNearest(shelterIndex: index, prefecture: "jp-tokyo", from: origin,
                                                hazardFilters: [\.flood])
        #expect(result.map(\.shelter.id) == ["mid", "far"])
    }

    @Test func 件数の上限で切り詰める() {
        let result = ShelterService.findNearest(shelterIndex: index, prefecture: "jp-tokyo", from: origin,
                                                hazardFilters: [\.flood, \.earthquake], limit: 1)
        #expect(result.map(\.shelter.id) == ["near"])
    }

    @Test func 未知の都道府県や災害種別の指定なしは空() {
        #expect(ShelterService.findNearest(shelterIndex: index, prefecture: "jp-unknown", from: origin,
                                           hazardFilters: [\.flood]).isEmpty)
        #expect(ShelterService.findNearest(shelterIndex: index, prefecture: "jp-tokyo", from: origin,
                                           hazardFilters: []).isEmpty)
    }

    @Test func 全国検索は都道府県をまたぐ() {
        let result = ShelterService.findNearestAll(shelterIndex: index, from: origin, hazardFilters: [\.flood], limit: 2)
        #expect(result.map(\.shelter.id) == ["other", "mid"])
    }
}

@MainActor
struct PrefectureTests {

    @Test func 正式名称で完全一致する() {
        #expect(Prefecture.from(japaneseName: "東京都") == .tokyo)
        #expect(Prefecture.from(japaneseName: "東京") == nil)
    }

    @Test(arguments: [
        ("東京", Prefecture.tokyo),
        ("東京都新宿区", .tokyo),
        ("京都", .kyoto),
        ("北海道札幌市", .hokkaido),
    ])
    func 部分一致で検索する(name: String, expected: Prefecture) {
        #expect(Prefecture.from(partialName: name) == expected)
    }

    @Test func 空文字は一致しない() {
        // hasPrefix("") は常に true のため、以前は先頭の北海道に一致していた
        #expect(Prefecture.from(partialName: "") == nil)
    }
}

extension ShelterHazards {
    static func stub(flood: Bool = false, earthquake: Bool = false) -> ShelterHazards {
        ShelterHazards(flood: flood, landslide: false, stormSurge: false, earthquake: earthquake,
                       tsunami: false, fire: false, inlandFlood: false, volcano: false)
    }
}
