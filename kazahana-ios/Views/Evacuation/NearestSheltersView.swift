// NearestSheltersView.swift
// kazahana-ios
// 最寄り避難所一覧画面

import SwiftUI
import CoreLocation

struct NearestSheltersView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(LocationService.self) private var locationService

    /// 都道府県別避難所インデックス（呼び出し元から渡す）
    let shelterIndex: [String: [Shelter]]

    @State private var selectedHazard: HazardType = .flood
    @State private var results: [ShelterWithDistance] = []
    @State private var isSearching = false
    @State private var resolvedPrefecture: String?

    var body: some View {
        List {
            // 災害種別フィルタ
            Section {
                Picker(String(localized: "evacuation.hazardFilter"), selection: $selectedHazard) {
                    ForEach(HazardType.allCases, id: \.self) { hazard in
                        Text(hazard.displayName).tag(hazard)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedHazard) {
                    search()
                }
            }

            // 位置情報の状態
            if !locationService.isAuthorized {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(String(localized: "evacuation.locationRequired"),
                              systemImage: "location.slash")
                        Button(String(localized: "evacuation.requestLocation")) {
                            locationService.requestPermission()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
            }

            // 検索結果
            if isSearching {
                Section {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            } else if results.isEmpty && locationService.currentLocation != nil {
                Section {
                    ContentUnavailableView {
                        Label(String(localized: "evacuation.noSheltersFound"),
                              systemImage: "building.2.slash")
                    }
                }
            } else {
                Section {
                    ForEach(results) { item in
                        NavigationLink {
                            ShelterDetailView(
                                shelter: item.shelter,
                                distance: item.distance
                            )
                            .environment(locationService)
                            .environment(settings)
                        } label: {
                            ShelterRow(item: item)
                        }
                    }
                } header: {
                    if !results.isEmpty {
                        Text(String(localized: "evacuation.nearestShelters"))
                    }
                }
            }

            // 免責表示
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "evacuation.dataSource"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "evacuation.dataWarning"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(String(localized: "evacuation.nearestShelters"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if locationService.isAuthorized {
                locationService.requestLocation()
            }
        }
        .onChange(of: locationService.currentLocation?.latitude) {
            search()
        }
        .onChange(of: locationService.authorizationStatus) {
            if locationService.isAuthorized {
                locationService.requestLocation()
            }
        }
    }

    // MARK: - 検索

    private func search() {
        guard let location = locationService.currentLocation else { return }
        isSearching = true

        let prefecture = settings.evacuationPrefectureOverride
            ?? resolvedPrefecture

        let hazardFilters = selectedHazard.keyPaths

        if let prefecture {
            results = ShelterService.findNearest(
                shelterIndex: shelterIndex,
                prefecture: prefecture,
                from: location,
                hazardFilters: hazardFilters,
                limit: 10
            )
        } else {
            // 都道府県不明時: 全検索（遅い可能性あり）
            results = ShelterService.findNearestAll(
                shelterIndex: shelterIndex,
                from: location,
                hazardFilters: hazardFilters,
                limit: 10
            )
            // バックグラウンドで都道府県を解決
            Task {
                if let pref = await ShelterService.resolvePrefecture(from: location) {
                    await MainActor.run { resolvedPrefecture = pref }
                }
            }
        }

        isSearching = false
    }
}

// MARK: - 避難所行

private struct ShelterRow: View {
    let item: ShelterWithDistance

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.shelter.name)
                .font(.subheadline.weight(.medium))
            HStack(spacing: 8) {
                Label(item.formattedDistance, systemImage: "location")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                hazardIcons
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var hazardIcons: some View {
        HStack(spacing: 4) {
            let h = item.shelter.hazards
            if h.flood       { hazardBadge("evacuation.hazard.flood") }
            if h.landslide   { hazardBadge("evacuation.hazard.landslide") }
            if h.stormSurge  { hazardBadge("evacuation.hazard.stormSurge") }
            if h.earthquake  { hazardBadge("evacuation.hazard.earthquake") }
            if h.tsunami     { hazardBadge("evacuation.hazard.tsunami") }
            if h.fire        { hazardBadge("evacuation.hazard.fire") }
            if h.inlandFlood { hazardBadge("evacuation.hazard.inlandFlood") }
            if h.volcano     { hazardBadge("evacuation.hazard.volcano") }
        }
    }

    private func hazardBadge(_ key: String) -> some View {
        Text(String(localized: String.LocalizationValue(key)))
            .font(.system(size: 9))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
            .foregroundStyle(.secondary)
    }
}

// MARK: - 災害種別フィルタ

enum HazardType: String, CaseIterable {
    case flood
    case landslide
    case stormSurge
    case earthquake
    case tsunami
    case fire
    case inlandFlood
    case volcano

    var displayName: String {
        switch self {
        case .flood:       return String(localized: "evacuation.hazard.flood")
        case .landslide:   return String(localized: "evacuation.hazard.landslide")
        case .stormSurge:  return String(localized: "evacuation.hazard.stormSurge")
        case .earthquake:  return String(localized: "evacuation.hazard.earthquake")
        case .tsunami:     return String(localized: "evacuation.hazard.tsunami")
        case .fire:        return String(localized: "evacuation.hazard.fire")
        case .inlandFlood: return String(localized: "evacuation.hazard.inlandFlood")
        case .volcano:     return String(localized: "evacuation.hazard.volcano")
        }
    }

    /// ShelterHazards の対応 KeyPath（OR 条件で使用）
    var keyPaths: [KeyPath<ShelterHazards, Bool>] {
        switch self {
        case .flood:       return [\.flood, \.inlandFlood]
        case .landslide:   return [\.landslide]
        case .stormSurge:  return [\.stormSurge]
        case .earthquake:  return [\.earthquake]
        case .tsunami:     return [\.tsunami]
        case .fire:        return [\.fire]
        case .inlandFlood: return [\.inlandFlood]
        case .volcano:     return [\.volcano]
        }
    }
}
