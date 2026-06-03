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
    let reason: String          // like / repost / follow / mention / reply / quote / verified / unverified
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

// MARK: - 通知グループ（同一投稿への同種アクションをまとめる）

struct NotificationGroup: Identifiable {
    let id: String
    let reason: String
    let reasonSubject: String?
    let notifications: [AppNotification]

    var latestNotification: AppNotification { notifications[0] }
    var authors: [ProfileViewBasic] { notifications.map(\.author) }
    var isRead: Bool { notifications.allSatisfy(\.isRead) }
    var indexedAt: String { latestNotification.indexedAt }
    var reasonIcon: String { latestNotification.reasonIcon }
    var reasonColor: Color { latestNotification.reasonColor }

    /// グループ用の表示ラベル。複数人の場合は「〇〇ほかN人が…」形式
    var groupLabel: String {
        let count = notifications.count
        guard count > 1 else { return latestNotification.reasonLabel }
        let name = latestNotification.author.displayName ?? latestNotification.author.handle
        let rest = count - 1
        switch reason {
        case "like":              return "\(name)ほか\(rest)人があなたの投稿をいいねしました"
        case "repost":            return "\(name)ほか\(rest)人があなたの投稿をリポストしました"
        case "like-via-repost":   return "\(name)ほか\(rest)人があなたのリポストをいいねしました"
        case "repost-via-repost": return "\(name)ほか\(rest)人があなたのリポストをリポストしました"
        default:                  return latestNotification.reasonLabel
        }
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
        case "like":              return String(localized: "notification.liked")
        case "repost":            return String(localized: "notification.reposted")
        case "like-via-repost":   return String(localized: "notification.likedViaRepost")
        case "repost-via-repost": return String(localized: "notification.repostedViaRepost")
        case "follow":            return String(localized: "notification.followed")
        case "mention":           return String(localized: "notification.mentioned")
        case "reply":             return String(localized: "notification.replied")
        case "quote":             return String(localized: "notification.quoted")
        case "verified":          return String(localized: "notification.verified")
        case "unverified":        return String(localized: "notification.unverified")
        default:                  return String(localized: "notification.default")
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
        case "verified":                    return "checkmark.seal.fill"
        case "unverified":                  return "xmark.seal.fill"
        default:                            return "bell.fill"
        }
    }

    var reasonColor: Color {
        switch reason {
        case "like", "like-via-repost":     return .red
        case "repost", "repost-via-repost": return .green
        case "follow":                      return .blue
        case "verified":                    return Color(hex: 0x0EA5E9)
        case "unverified":                  return .orange
        default:                            return .secondary
        }
    }
}
