// MediaSaveHelper.swift
// kazahana-ios
// 画像・動画をフォトライブラリに保存するユーティリティ

import Photos
import UIKit

enum MediaSaveHelper {

    // MARK: - 保存可能なメディアが含まれるか判定

    static func hasMedia(in embed: PostEmbed?) -> Bool {
        guard let embed else { return false }
        switch embed {
        case .images(let imgs):         return !imgs.images.isEmpty
        case .video:                    return true
        case .recordWithMedia(let rwm):
            guard let media = rwm.media else { return false }
            switch media {
            case .images(let imgs): return !imgs.images.isEmpty
            case .video:            return true
            default:                return false
            }
        default: return false
        }
    }

    // MARK: - フォトライブラリへの保存（権限取得を含む）

    /// embed に含まれる画像・動画をすべてフォトライブラリに保存する。
    /// - Returns: 保存に成功したアイテム数
    @discardableResult
    static func save(embed: PostEmbed?) async -> Int {
        // 権限確認
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return 0 }

        guard let embed else { return 0 }
        var count = 0

        switch embed {
        case .images(let imgs):
            count += await saveImages(imgs.images)
        case .video(let video):
            if let playlist = video.playlist, await saveVideo(playlistURL: playlist) { count += 1 }
        case .recordWithMedia(let rwm):
            if let media = rwm.media {
                switch media {
                case .images(let imgs):
                    count += await saveImages(imgs.images)
                case .video(let video):
                    if let playlist = video.playlist, await saveVideo(playlistURL: playlist) { count += 1 }
                default: break
                }
            }
        default: break
        }
        return count
    }

    // MARK: - 内部ヘルパー

    /// 画像リストを順次保存し、成功数を返す
    private static func saveImages(_ images: [EmbedImageView]) async -> Int {
        var count = 0
        for image in images {
            guard let url = URL(string: image.fullsize),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let uiImage = UIImage(data: data) else { continue }
            let saved = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
                }) { success, _ in
                    continuation.resume(returning: success)
                }
            }
            if saved { count += 1 }
        }
        return count
    }

    /// HLS playlist URL → video.mp4 に変換してダウンロード・保存する
    private static func saveVideo(playlistURL: String) async -> Bool {
        guard let url = URL(string: playlistURL) else { return false }
        let mp4URL = url.deletingLastPathComponent().appendingPathComponent("video.mp4")

        guard let (data, _) = try? await URLSession.shared.data(from: mp4URL) else { return false }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        guard (try? data.write(to: tempURL)) != nil else { return false }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempURL)
            }) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
