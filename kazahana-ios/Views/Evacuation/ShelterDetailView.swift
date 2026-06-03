// ShelterDetailView.swift
// kazahana-ios
// 避難所詳細画面（施設情報・ナビ・簡易ナビ）

import SwiftUI
import CoreLocation
import Network

struct ShelterDetailView: View {

    let shelter: Shelter
    let distance: Double

    @Environment(LocationService.self) private var locationService: LocationService?
    @Environment(AppSettings.self) private var settings
    @State private var isOnline = true
    @State private var pathMonitor: NWPathMonitor?
    @State private var showCompassNav = false

    var body: some View {
        List {
            // 施設情報
            Section {
                LabeledContent(String(localized: "evacuation.shelterName")) {
                    Text(shelter.name)
                }

                LabeledContent(String(localized: "evacuation.distance")) {
                    Text(ShelterWithDistance(shelter: shelter, distance: distance).formattedDistance)
                }

                LabeledContent(String(localized: "evacuation.coordinates")) {
                    Text(String(format: "%.5f, %.5f", shelter.lat, shelter.lng))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(String(localized: "evacuation.shelterInfo"))
            }

            // 対応災害種別
            Section {
                hazardRow("evacuation.hazard.flood", supported: shelter.hazards.flood)
                hazardRow("evacuation.hazard.landslide", supported: shelter.hazards.landslide)
                hazardRow("evacuation.hazard.stormSurge", supported: shelter.hazards.stormSurge)
                hazardRow("evacuation.hazard.earthquake", supported: shelter.hazards.earthquake)
                hazardRow("evacuation.hazard.tsunami", supported: shelter.hazards.tsunami)
                hazardRow("evacuation.hazard.fire", supported: shelter.hazards.fire)
                hazardRow("evacuation.hazard.inlandFlood", supported: shelter.hazards.inlandFlood)
                hazardRow("evacuation.hazard.volcano", supported: shelter.hazards.volcano)
            } header: {
                Text(String(localized: "evacuation.supportedHazards"))
            }

            // ナビゲーション
            Section {
                // Apple Maps ナビ（オフライン時は非活性）
                Button {
                    ShelterService.openInMaps(shelter: shelter)
                } label: {
                    Label(String(localized: "evacuation.openInMaps"), systemImage: "map")
                }
                .disabled(!isOnline)

                // 簡易コンパスナビ（フルスクリーン表示 — スワイプダウンで閉じない）
                #if !targetEnvironment(macCatalyst)
                Button {
                    showCompassNav = true
                } label: {
                    HStack {
                        Label(String(localized: "evacuation.compassNav"), systemImage: "location.north.fill")
                        if !isOnline {
                            Spacer()
                            Text(String(localized: "evacuation.recommended"))
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(.blue)
                        }
                    }
                }
                #endif

                // オフラインメッセージ
                if !isOnline {
                    Label(String(localized: "evacuation.offlineNote"),
                          systemImage: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text(String(localized: "evacuation.navigation"))
            }

            // 免責・出典
            Section {
                Text(String(localized: "evacuation.disclaimer"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(localized: "evacuation.dataSource"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(String(localized: "evacuation.dataWarning"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(shelter.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showCompassNav) {
            NavigationStack {
                CompassNavView(shelter: shelter)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "evacuation.closeCompass")) {
                                showCompassNav = false
                            }
                        }
                    }
            }
        }
        .onAppear { startNetworkMonitor() }
        .onDisappear { stopNetworkMonitor() }
    }

    // MARK: - 災害種別行

    @ViewBuilder
    private func hazardRow(_ key: String, supported: Bool) -> some View {
        HStack {
            Text(String(localized: String.LocalizationValue(key)))
                .font(.subheadline)
            Spacer()
            Image(systemName: supported ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(supported ? .green : .secondary.opacity(0.4))
        }
    }

    // MARK: - ネットワーク監視

    private func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            Task { @MainActor in
                isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
        pathMonitor = monitor
    }

    private func stopNetworkMonitor() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }
}
