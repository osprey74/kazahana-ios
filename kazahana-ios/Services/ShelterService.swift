// ShelterService.swift
// kazahana-ios
// 避難所データの読み込み・最近傍探索・ナビ委譲

import Foundation
import CoreLocation
import MapKit

struct ShelterService {

    // MARK: - データ読み込み

    /// Bundle 同梱の避難所データを読み込み、都道府県別にインデックスして返す
    static func loadShelters() -> [String: [Shelter]] {
        guard let url = Bundle.main.url(forResource: "shelters", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let shelters = try? JSONDecoder().decode([Shelter].self, from: data)
        else { return [:] }
        return Dictionary(grouping: shelters, by: \.prefecture)
    }

    // MARK: - 最近傍探索

    /// 指定都道府県の避難所から最近傍を探索
    /// - shelterIndex: loadShelters() の戻り値（都道府県別インデックス）
    /// - prefecture: jp-xxxx 形式の都道府県コード
    /// - location: 現在地
    /// - hazardFilters: 災害種別フィルタ（OR 条件。いずれかに対応する施設を候補化）
    /// - limit: 返却件数上限
    static func findNearest(
        shelterIndex: [String: [Shelter]],
        prefecture: String,
        from location: CLLocationCoordinate2D,
        hazardFilters: [KeyPath<ShelterHazards, Bool>],
        limit: Int = 5
    ) -> [ShelterWithDistance] {
        guard let shelters = shelterIndex[prefecture] else { return [] }
        return shelters
            .filter { shelter in
                hazardFilters.contains { shelter.hazards[keyPath: $0] }
            }
            .map { shelter in
                let distance = haversineDistance(
                    lat1: location.latitude, lng1: location.longitude,
                    lat2: shelter.lat, lng2: shelter.lng
                )
                return ShelterWithDistance(shelter: shelter, distance: distance)
            }
            .sorted { $0.distance < $1.distance }
            .prefix(limit)
            .map { $0 }
    }

    /// 全都道府県横断で最近傍を探索（都道府県不明時のフォールバック）
    static func findNearestAll(
        shelterIndex: [String: [Shelter]],
        from location: CLLocationCoordinate2D,
        hazardFilters: [KeyPath<ShelterHazards, Bool>],
        limit: Int = 5
    ) -> [ShelterWithDistance] {
        let allShelters = shelterIndex.values.flatMap { $0 }
        return allShelters
            .filter { shelter in
                hazardFilters.contains { shelter.hazards[keyPath: $0] }
            }
            .map { shelter in
                let distance = haversineDistance(
                    lat1: location.latitude, lng1: location.longitude,
                    lat2: shelter.lat, lng2: shelter.lng
                )
                return ShelterWithDistance(shelter: shelter, distance: distance)
            }
            .sorted { $0.distance < $1.distance }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Haversine 距離計算

    /// 2点間の Haversine 距離（メートル）
    static func haversineDistance(lat1: Double, lng1: Double, lat2: Double, lng2: Double) -> Double {
        let R = 6_371_000.0 // 地球半径（m）
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }

    // MARK: - 方位角計算

    /// 2点間の方位角を計算（度、真北基準で時計回り）
    static func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let dLng = (end.longitude - start.longitude) * .pi / 180
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let y = sin(dLng) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng)
        let bearing = atan2(y, x) * 180 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }

    // MARK: - 都道府県判定

    /// CLGeocoder で緯度経度から都道府県を判定し jp-xxxx に変換
    /// オフライン時は nil を返す（手動設定にフォールバック）
    static func resolvePrefecture(from coordinate: CLLocationCoordinate2D) async -> String? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemarks = try? await geocoder.reverseGeocodeLocation(location),
              let state = placemarks.first?.administrativeArea
        else { return nil }
        return Prefecture.from(japaneseName: state)?.rawValue
    }

    // MARK: - OS ナビ委譲

    /// Apple Maps で避難所への徒歩ナビを起動
    static func openInMaps(shelter: Shelter) {
        let coordinate = CLLocationCoordinate2D(latitude: shelter.lat, longitude: shelter.lng)
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = shelter.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }
}
