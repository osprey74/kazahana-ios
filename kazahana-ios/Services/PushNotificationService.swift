// PushNotificationService.swift
// kazahana-ios
// APNs デバイストークン管理・通知許可・バッジリセット

import UIKit
import UserNotifications

/// APNs プッシュ通知のデバイストークンを管理し、kazahana-push-backend に登録・削除するサービス。
/// シングルトン。アカウント切替・ログアウト時に AuthViewModel から呼ばれる。
final class PushNotificationService {

    static let shared = PushNotificationService()
    private init() {
        // UserDefaults から前回保存済みトークンを復元
        deviceToken = UserDefaults.standard.string(forKey: "apnsDeviceToken")
    }

    // MARK: - 定数

    private let backendURL = "https://kazahana-push-backend.fly.dev"
    private let apiSecret = "G(|2NLm2W&MtF%uN"

    // MARK: - State

    /// 現在のデバイストークン（hex文字列）。APNs から取得後に設定される。
    private(set) var deviceToken: String? {
        didSet { UserDefaults.standard.set(deviceToken, forKey: "apnsDeviceToken") }
    }

    // MARK: - 通知許可リクエスト

    /// 通知許可ダイアログを表示し、許可された場合に APNs デバイストークンを要求する。
    /// ログイン成功後に AuthViewModel から呼ぶ。
    @MainActor
    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        // すでに許否済みの場合はダイアログを再表示しない
        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } catch {
                print("[Push] Permission request failed: \(error)")
            }
        case .authorized, .provisional:
            // 許可済み: 念のため再登録（トークンが変わっている場合に対応）
            UIApplication.shared.registerForRemoteNotifications()
        default:
            break
        }
    }

    // MARK: - デバイストークン受信（AppDelegate から呼ぶ）

    /// APNs から新しいデバイストークンを受け取ったときに AppDelegate から呼ぶ。
    func didReceiveDeviceToken(_ tokenData: Data) {
        let tokenString = tokenData.map { String(format: "%02x", $0) }.joined()
        deviceToken = tokenString
        print("[Push] Device token: \(tokenString)")
        // 保存済み全アカウントに対してトークンを登録
        Task { await registerTokenForAllAccounts() }
    }

    // MARK: - トークン登録

    /// 指定 DID のデバイストークンをバックエンドに登録する。
    /// ベストエフォート（失敗時はログのみ）。
    func registerToken(for did: String) async {
        guard let token = deviceToken else {
            print("[Push] No device token yet, skipping registration for \(did)")
            return
        }
        await callBackend(
            method: "POST",
            path: "/api/device-token",
            body: ["did": did, "token": token, "platform": "ios"]
        )
        print("[Push] Registered token for \(did)")
    }

    /// 保存済み全アカウント（全 DID）に対してデバイストークンを登録する。
    /// アプリ起動時・新規トークン取得時に呼ぶ。
    func registerTokenForAllAccounts() async {
        let sessions = SessionStore().loadAll()
        for session in sessions {
            await registerToken(for: session.did)
        }
    }

    // MARK: - トークン削除

    /// 指定 DID のデバイストークンをバックエンドから削除する。
    /// アカウント削除時・ログアウト時に AuthViewModel から呼ぶ。
    func unregisterToken(for did: String) async {
        await callBackend(
            method: "DELETE",
            path: "/api/device-token",
            body: ["did": did, "platform": "ios"]
        )
        print("[Push] Unregistered token for \(did)")
    }

    // MARK: - バッジリセット

    /// アプリアイコンのバッジをクリアする。
    /// アプリ起動時・フォアグラウンド復帰時に呼ぶ。
    func resetBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0) { error in
            if let error { print("[Push] Badge reset error: \(error)") }
        }
    }

    // MARK: - Private

    private func callBackend(method: String, path: String, body: [String: String]) async {
        guard let url = URL(string: backendURL + path) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiSecret)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                print("[Push] Backend \(method) \(path) returned HTTP \(http.statusCode)")
            }
        } catch {
            print("[Push] Backend \(method) \(path) error: \(error)")
        }
    }
}
