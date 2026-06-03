// CompassNavView.swift
// kazahana-ios
// 簡易コンパスナビ（オフライン最終防衛線）
// 同梱避難所データ + CoreLocation heading で方向・距離を表示

import SwiftUI
import CoreLocation

struct CompassNavView: View {
    let shelter: Shelter
    @Environment(LocationService.self) private var locationService: LocationService?

    var body: some View {
        VStack(spacing: 24) {
            // 施設名
            Text(shelter.name)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            #if !targetEnvironment(macCatalyst)
            // iOS: コンパス矢印
            compassSection
            #else
            // macOS: コンパス非対応
            macUnavailableSection
            #endif

            // 直線距離（プラットフォーム共通）
            distanceSection

            Spacer()

            // 免責
            VStack(spacing: 4) {
                Text(String(localized: "evacuation.compassDisclaimer"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(String(localized: "evacuation.disclaimer"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 24)
        .navigationTitle(String(localized: "evacuation.compassNav"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            locationService?.startUpdatingLocation()
            locationService?.startUpdatingHeading()
        }
        .onDisappear {
            locationService?.stopUpdatingLocation()
            locationService?.stopUpdatingHeading()
        }
    }

    // MARK: - コンパスセクション（iOS）

    @ViewBuilder
    private var compassSection: some View {
        ZStack {
            // 外周リング
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 2)
                .frame(width: 200, height: 200)

            // 方角ラベル
            compassCardinalLabels

            // 矢印
            Image(systemName: "location.north.fill")
                .font(.system(size: 64))
                .rotationEffect(.degrees(arrowRotation))
                .animation(.easeInOut(duration: 0.3), value: arrowRotation)
                .foregroundStyle(.blue)
        }
        .frame(width: 220, height: 220)

        // 精度警告
        if let service = locationService {
            if !service.isHeadingAvailable {
                Label(String(localized: "evacuation.compassUnavailableMac"),
                      systemImage: "location.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if service.headingAccuracy < 0 {
                Label(String(localized: "evacuation.compassCalibration"),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// 東西南北ラベル
    @ViewBuilder
    private var compassCardinalLabels: some View {
        let labels = [("N", 0.0), ("E", 90.0), ("S", 180.0), ("W", 270.0)]
        ForEach(labels, id: \.0) { label, angle in
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .offset(y: -108)
                .rotationEffect(.degrees(angle))
        }
    }

    // MARK: - macOS 非対応セクション

    @ViewBuilder
    private var macUnavailableSection: some View {
        ContentUnavailableView {
            Label(String(localized: "evacuation.compassUnavailableMac"),
                  systemImage: "location.slash")
        } description: {
            Text(String(localized: "evacuation.useMapAppInstead"))
        } actions: {
            Button(String(localized: "evacuation.openInMaps")) {
                ShelterService.openInMaps(shelter: shelter)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - 距離セクション

    @ViewBuilder
    private var distanceSection: some View {
        if let location = locationService?.currentLocation {
            let dist = ShelterService.haversineDistance(
                lat1: location.latitude, lng1: location.longitude,
                lat2: shelter.lat, lng2: shelter.lng
            )
            VStack(spacing: 4) {
                Text(formatDistance(dist))
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                Text(String(localized: "evacuation.straightLineDistance"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 8) {
                ProgressView()
                Text(String(localized: "evacuation.locating"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 計算

    private var arrowRotation: Double {
        guard let location = locationService?.currentLocation else { return 0 }
        let target = CLLocationCoordinate2D(latitude: shelter.lat, longitude: shelter.lng)
        let bearing = ShelterService.bearing(from: location, to: target)
        return bearing - (locationService?.heading ?? 0)
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }
}
