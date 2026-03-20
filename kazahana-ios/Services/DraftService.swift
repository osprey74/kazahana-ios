// DraftService.swift
// kazahana-ios
// 下書きの保存・読み込み・削除を管理するサービス

import Foundation
import UIKit

/// 下書きサービス（最大20件、画像/動画はファイルシステムに保存）
final class DraftService {

    static let shared = DraftService()

    private static let maxDrafts = 20
    private static let metadataKey = "postDrafts"

    // Documents/drafts/ ディレクトリ
    private var draftsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("drafts", isDirectory: true)
    }

    private init() {
        try? FileManager.default.createDirectory(at: draftsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - 読み込み

    func loadAll() -> [PostDraft] {
        guard let data = UserDefaults.standard.data(forKey: Self.metadataKey),
              let drafts = try? JSONDecoder().decode([PostDraft].self, from: data) else {
            return []
        }
        return drafts.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - 保存

    /// 下書きを保存する（画像/動画はファイルに書き出す）
    func save(
        text: String,
        images: [(image: UIImage, alt: String)],
        video: (data: Data, mimeType: String, alt: String)?,
        threadgateIndex: Int,
        disableEmbedding: Bool
    ) {
        var drafts = loadAll()

        let draftID = UUID()

        // 画像を保存
        var imageMetas: [DraftImageMeta] = []
        for (i, item) in images.enumerated() {
            let filename = "\(draftID.uuidString)_img_\(i).jpg"
            let fileURL = draftsDirectory.appendingPathComponent(filename)
            if let jpegData = item.image.jpegData(compressionQuality: 0.85) {
                try? jpegData.write(to: fileURL)
                imageMetas.append(DraftImageMeta(filename: filename, alt: item.alt))
            }
        }

        // 動画を保存
        var videoMeta: DraftVideoMeta? = nil
        if let v = video {
            let ext = v.mimeType.contains("quicktime") ? "mov" : "mp4"
            let filename = "\(draftID.uuidString)_video.\(ext)"
            let fileURL = draftsDirectory.appendingPathComponent(filename)
            try? v.data.write(to: fileURL)
            videoMeta = DraftVideoMeta(filename: filename, mimeType: v.mimeType, alt: v.alt)
        }

        let draft = PostDraft(
            id: draftID,
            createdAt: Date(),
            text: text,
            images: imageMetas,
            video: videoMeta,
            threadgateIndex: threadgateIndex,
            disableEmbedding: disableEmbedding
        )

        drafts.insert(draft, at: 0)

        // 最大件数を超えたら古いものから削除
        if drafts.count > Self.maxDrafts {
            let toRemove = drafts.suffix(from: Self.maxDrafts)
            for old in toRemove {
                deleteFiles(for: old)
            }
            drafts = Array(drafts.prefix(Self.maxDrafts))
        }

        persist(drafts)
    }

    // MARK: - 削除

    func delete(id: UUID) {
        var drafts = loadAll()
        if let idx = drafts.firstIndex(where: { $0.id == id }) {
            deleteFiles(for: drafts[idx])
            drafts.remove(at: idx)
        }
        persist(drafts)
    }

    func deleteAll() {
        let drafts = loadAll()
        for draft in drafts {
            deleteFiles(for: draft)
        }
        UserDefaults.standard.removeObject(forKey: Self.metadataKey)
    }

    // MARK: - ファイル読み込み（復元用）

    func imageData(for meta: DraftImageMeta) -> Data? {
        let url = draftsDirectory.appendingPathComponent(meta.filename)
        return try? Data(contentsOf: url)
    }

    func videoData(for meta: DraftVideoMeta) -> Data? {
        let url = draftsDirectory.appendingPathComponent(meta.filename)
        return try? Data(contentsOf: url)
    }

    // MARK: - Private

    private func persist(_ drafts: [PostDraft]) {
        if let data = try? JSONEncoder().encode(drafts) {
            UserDefaults.standard.set(data, forKey: Self.metadataKey)
        }
    }

    private func deleteFiles(for draft: PostDraft) {
        for img in draft.images {
            let url = draftsDirectory.appendingPathComponent(img.filename)
            try? FileManager.default.removeItem(at: url)
        }
        if let vid = draft.video {
            let url = draftsDirectory.appendingPathComponent(vid.filename)
            try? FileManager.default.removeItem(at: url)
        }
    }
}
