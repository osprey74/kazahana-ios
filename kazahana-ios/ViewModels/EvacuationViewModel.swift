// EvacuationViewModel.swift
// kazahana-ios
// 避難誘導バナー状態管理（ContentView レベルで保持し、アカウント切替の影響を受けない）

import Foundation
import Observation

@Observable
final class EvacuationViewModel {

    // MARK: - バナー状態

    /// バナーを表示するか
    var bannerVisible: Bool = false

    /// アクティブなアラートの中で最も高いレベル
    var highestLevel: AlertLevel? = nil

    /// アクティブなアラート一覧
    var activeAlerts: [ActiveAlert] = []

    // MARK: - 設定参照

    private let settings: AppSettings

    /// タイムアウト時間（時間）。cancelled 見逃し対策。
    private let alertTimeoutHours: Double = 6.0

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - 現在の都道府県

    /// 現在の判定対象都道府県（手動設定 or 位置情報由来）
    /// 位置情報由来は外部から設定する
    var currentPrefecture: String? {
        settings.evacuationPrefectureOverride ?? locationDerivedPrefecture
    }

    /// 位置情報から判定された都道府県（外部から更新可能）
    var locationDerivedPrefecture: String?

    // MARK: - アラート処理

    /// BSAF 投稿を処理し、バナー状態を更新
    @MainActor
    func processPost(tags: BsafParsedTags) {
        guard settings.evacuationEnabled else { return }
        guard let prefecture = currentPrefecture else { return }

        // cancelled 処理
        if tags.value == "cancelled" {
            removeCancelledAlerts(type: tags.type, target: tags.target)
            return
        }

        // レベル3以上 かつ 対象都道府県の判定
        guard EvacuationAlertService.isEvacuationTrigger(tags, prefecture: prefecture) else { return }
        guard let level = EvacuationAlertService.toAlertLevel(tags.value) else { return }

        let alert = ActiveAlert(
            type: tags.type,
            value: level,
            time: tags.time,
            target: tags.target,
            receivedAt: Date()
        )

        // 重複排除（type + value + time + target の完全一致）
        guard !activeAlerts.contains(where: { $0.id == alert.id }) else { return }

        activeAlerts.append(alert)
        updateBannerState()
    }

    /// タイムアウトした古いアラートを除去（scenePhase 復帰時 + Timer から呼ばれる）
    @MainActor
    func expireStaleAlerts() {
        let cutoff = Date().addingTimeInterval(-alertTimeoutHours * 3600)
        let before = activeAlerts.count
        activeAlerts.removeAll { $0.receivedAt < cutoff }
        if activeAlerts.count != before {
            updateBannerState()
        }
    }

    /// 全アラートをクリア（機能オフ時に呼ぶ）
    @MainActor
    func clearAll() {
        activeAlerts.removeAll()
        updateBannerState()
    }

    // MARK: - デバッグ用シミュレーション

    #if DEBUG
    /// テスト用アラートを注入（DEBUG ビルドのみ）
    @MainActor
    func injectTestAlert(level: AlertLevel, type: String = "heavy-rain-warning") {
        let prefecture = currentPrefecture ?? "jp-tokyo"
        let alert = ActiveAlert(
            type: type,
            value: level,
            time: ISO8601DateFormatter().string(from: Date()),
            target: prefecture,
            receivedAt: Date()
        )
        guard !activeAlerts.contains(where: { $0.id == alert.id }) else { return }
        activeAlerts.append(alert)
        updateBannerState()
    }
    #endif

    // MARK: - Private

    @MainActor
    private func removeCancelledAlerts(type: String, target: String) {
        activeAlerts.removeAll { $0.type == type && $0.target == target }
        updateBannerState()
    }

    @MainActor
    private func updateBannerState() {
        if activeAlerts.isEmpty {
            bannerVisible = false
            highestLevel = nil
        } else {
            bannerVisible = true
            highestLevel = activeAlerts.map(\.value).max()
        }
    }
}
