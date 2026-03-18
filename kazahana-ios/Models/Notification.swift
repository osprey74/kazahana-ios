// Notification.swift
// kazahana-ios
// 通知関連モデル

import Foundation
import SwiftUI

// MARK: - 通知一覧レスポンス

struct NotificationListResponse: Codable {
    let notifications: [AppNotification]
    let cursor: String?
    let seenAt: String?
}

struct UnreadCountResponse: Codable {
    let count: Int
}

// MARK: - 通知アイテム

struct AppNotification: Codable, Identifiable, Hashable {
    let uri: String
    let cid: String
    let author: ProfileViewBasic
    let reason: String          // like / repost / follow / mention / reply / quote
    let reasonSubject: String?
    let record: NotificationRecord
    let isRead: Bool
    let indexedAt: String

    var id: String { uri }

    static func == (lhs: AppNotification, rhs: AppNotification) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct NotificationRecord: Codable {
    let type: String?
    let text: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case text
        case createdAt
    }
}

// MARK: - 通知の種別

extension AppNotification {
    /// reasonSubject がリポストレコードを指しているか
    var isRepostSubject: Bool {
        reasonSubject?.contains("/app.bsky.feed.repost/") == true
    }

    /// like-via-repost / repost-via-repost 通知かどうか
    var isViaRepost: Bool {
        reason == "like-via-repost" || reason == "repost-via-repost"
    }

    var reasonLabel: String {
        switch reason {
        case "like":              return "があなたの投稿をいいねしました"
        case "repost":            return "があなたの投稿をリポストしました"
        case "like-via-repost":   return "があなたのリポストをいいねしました"
        case "repost-via-repost": return "があなたのリポストをリポストしました"
        case "follow":            return "があなたをフォローしました"
        case "mention":           return "があなたをメンションしました"
        case "reply":             return "があなたの投稿に返信しました"
        case "quote":             return "があなたの投稿を引用しました"
        default:                  return "からの通知"
        }
    }

    var reasonIcon: String {
        switch reason {
        case "like", "like-via-repost":     return "heart.fill"
        case "repost", "repost-via-repost": return "arrow.2.squarepath"
        case "follow":                      return "person.badge.plus"
        case "mention":                     return "at"
        case "reply":                       return "bubble.left.fill"
        case "quote":                       return "quote.bubble.fill"
        default:                            return "bell.fill"
        }
    }

    var reasonColor: Color {
        switch reason {
        case "like", "like-via-repost":     return .red
        case "repost", "repost-via-repost": return .green
        case "follow":                      return .blue
        default:                            return .secondary
        }
    }
}
