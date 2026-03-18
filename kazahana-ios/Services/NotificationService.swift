// NotificationService.swift
// kazahana-ios
// 通知取得・既読更新サービス

import Foundation

final class NotificationService {

    private let client: ATProtoClient

    init(client: ATProtoClient) {
        self.client = client
    }

    // MARK: - 通知一覧取得

    func listNotifications(limit: Int = 50, cursor: String? = nil) async throws -> NotificationListResponse {
        var params: [String: String] = ["limit": "\(limit)"]
        if let cursor { params["cursor"] = cursor }
        return try await client.get(
            nsid: "app.bsky.notification.listNotifications",
            params: params
        )
    }

    // MARK: - 未読件数

    func getUnreadCount() async throws -> Int {
        let response: UnreadCountResponse = try await client.get(
            nsid: "app.bsky.notification.getUnreadCount"
        )
        return response.count
    }

    // MARK: - 既読マーク

    func updateSeen(seenAt: Date = Date()) async throws {
        let body = ["seenAt": ISO8601DateFormatter().string(from: seenAt)]
        let _: EmptyResponse = try await client.post(
            nsid: "app.bsky.notification.updateSeen",
            body: body
        )
    }
}
