// LocationService.swift
// kazahana-ios
// CoreLocation ラッパー（位置情報・コンパス）
// アプリ全体で1インスタンスを共有し @Environment で配布する

import Foundation
import CoreLocation
import Observation

@Observable
final class LocationService {

    // MARK: - 公開プロパティ

    /// 現在地（nil = 未取得）
    var currentLocation: CLLocationCoordinate2D?

    /// 位置情報の認可状態
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// デバイスの向き（真北からの度数、コンパスナビ用）
    var heading: Double = 0

    /// コンパスの精度（< 0 = キャリブレーション不良）
    var headingAccuracy: Double = -1

    /// エラーメッセージ
    var errorMessage: String?

    // MARK: - Private

    private let manager = CLLocationManager()
    private var delegate: Delegate?

    // MARK: - Init

    init() {
        let delegate = Delegate(owner: self)
        self.delegate = delegate
        manager.delegate = delegate
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    // MARK: - 権限

    /// 位置情報の権限をリクエスト（WhenInUse のみ）
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// 位置情報が利用可能か
    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    // MARK: - 位置情報

    /// 現在地を一回取得（避難所一覧画面用）
    func requestLocation() {
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.requestLocation()
    }

    /// 連続測位を開始（コンパスナビ用：リアルタイム距離更新）
    func startUpdatingLocation() {
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10  // 10m ごとに更新（バッテリー節約）
        manager.startUpdatingLocation()
    }

    /// 連続測位を停止
    func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
    }

    // MARK: - コンパス

    /// コンパス（heading）の更新を開始
    func startUpdatingHeading() {
        guard CLLocationManager.headingAvailable() else { return }
        manager.startUpdatingHeading()
    }

    /// コンパス（heading）の更新を停止
    func stopUpdatingHeading() {
        manager.stopUpdatingHeading()
    }

    /// コンパスが利用可能か
    var isHeadingAvailable: Bool {
        CLLocationManager.headingAvailable()
    }

    // MARK: - 内部デリゲート（NSObject 継承を @Observable から分離）

    private class Delegate: NSObject, CLLocationManagerDelegate {
        private unowned let owner: LocationService

        init(owner: LocationService) {
            self.owner = owner
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            owner.currentLocation = locations.last?.coordinate
        }

        func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
            // trueHeading が有効ならそれを使う（GPS 補正済み）、なければ magneticHeading
            owner.heading = newHeading.trueHeading >= 0
                ? newHeading.trueHeading : newHeading.magneticHeading
            owner.headingAccuracy = newHeading.headingAccuracy
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            // 位置情報一時取得失敗は致命的ではないのでメッセージのみ
            owner.errorMessage = error.localizedDescription
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            owner.authorizationStatus = manager.authorizationStatus
        }
    }
}
