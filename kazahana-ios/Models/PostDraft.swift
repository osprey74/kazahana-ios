// PostDraft.swift
// kazahana-ios
// 下書きデータモデル

import Foundation

/// 下書き画像のメタデータ（実データはファイルシステムに保存）
struct DraftImageMeta: Codable {
    let filename: String   // Documents/drafts/ 配下のファイル名
    var alt: String
}

/// 下書き動画のメタデータ（実データはファイルシステムに保存）
struct DraftVideoMeta: Codable {
    let filename: String   // Documents/drafts/ 配下のファイル名
    var mimeType: String
    var alt: String
}

/// 投稿下書きモデル
struct PostDraft: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    var text: String
    var images: [DraftImageMeta]
    var video: DraftVideoMeta?
    /// ThreadgateSetting の allCases インデックス（0 = everyone）
    var threadgateIndex: Int
    var disableEmbedding: Bool
}
