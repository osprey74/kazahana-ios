// Profile.swift
// kazahana-ios
// プロフィール関連モデル

import Foundation

// MARK: - 基本プロフィール（投稿カード等で使用）

struct ProfileViewBasic: Codable {
    let did: String
    let handle: String
    let displayName: String?
    let avatar: String?
    let viewer: ActorViewerState?
    let labels: [ContentLabel]?
    let createdAt: String?

    /// 表示名（displayName があればそちら、なければ handle）
    var displayNameOrHandle: String {
        let name = displayName ?? ""
        return name.isEmpty ? handle : name
    }
}

// MARK: - 詳細プロフィール（プロフィール画面で使用）

struct ProfileView: Codable {
    let did: String
    let handle: String
    let displayName: String?
    let description: String?
    let avatar: String?
    let banner: String?
    let followersCount: Int?
    let followsCount: Int?
    let postsCount: Int?
    let viewer: ActorViewerState?
    let labels: [ContentLabel]?
    let createdAt: String?

    var displayNameOrHandle: String {
        let name = displayName ?? ""
        return name.isEmpty ? handle : name
    }
}

// MARK: - アクター間の関係

struct ActorViewerState: Codable {
    let muted: Bool?
    let blockedBy: Bool?
    let blocking: String?
    let following: String?
    let followedBy: String?
}
