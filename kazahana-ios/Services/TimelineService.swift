// TimelineService.swift
// kazahana-ios
// タイムライン取得サービス

import Foundation

final class TimelineService {

    private let client: ATProtoClient

    init(client: ATProtoClient) {
        self.client = client
    }

    // MARK: - ホームタイムライン

    /// ホームタイムラインを取得する
    /// - Parameters:
    ///   - limit: 取得件数 (1-100, デフォルト50)
    ///   - cursor: ページネーション用カーソル
    /// - Returns: TimelineResponse
    func getTimeline(limit: Int = 50, cursor: String? = nil) async throws -> TimelineResponse {
        var params: [String: String] = ["limit": "\(limit)"]
        if let cursor {
            params["cursor"] = cursor
        }
        return try await client.get(
            nsid: "app.bsky.feed.getTimeline",
            params: params
        )
    }
}
