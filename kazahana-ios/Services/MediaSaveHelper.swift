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
        case .gallery(let gallery):     return !gallery.items.isEmpty
        case .video:                    return true
        case .recordWithMedia(let rwm):
            guard let media = rwm.media else { return false }
            switch media {
            case .images(let imgs):     return !imgs.images.isEmpty
            case .gallery(let gallery): return !gallery.items.isEmpty
            case .video:                return true
            default:                    return false
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
        guard status == .authorized || status == .limited else {
            print("[MediaSave] Authorization denied: \(status.rawValue)")
            return 0
        }

        guard let embed else { return 0 }
        var count = 0

        switch embed {
        case .images(let imgs):
            count += await saveImages(imgs.images)
        case .gallery(let gallery):
            count += await saveImages(gallery.items)
        case .video(let video):
            if let playlist = video.playlist, await saveVideo(playlistURL: playlist) { count += 1 }
        case .recordWithMedia(let rwm):
            if let media = rwm.media {
                switch media {
                case .images(let imgs):
                    count += await saveImages(imgs.images)
                case .gallery(let gallery):
                    count += await saveImages(gallery.items)
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
            guard let url = URL(string: image.fullsize) else {
                print("[MediaSave] Invalid URL: \(image.fullsize)")
                continue
            }

            guard let (data, _) = try? await URLSession.shared.data(from: url), !data.isEmpty else {
                print("[MediaSave] Download failed for: \(url)")
                continue
            }

            let saved = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: data, options: nil)
                }, completionHandler: { success, error in
                    if let error = error {
                        print("[MediaSave] performChanges error: \(error.localizedDescription)")
                    }
                    continuation.resume(returning: success)
                })
            }
            if saved { count += 1 }
        }
        return count
    }

    /// playlist URL から DID・CID を抽出し、AT Protocol getBlob で動画を取得して保存する
    /// playlist URL 形式: https://video.bsky.app/watch/{did}/{cid}/playlist.m3u8
    private static func saveVideo(playlistURL: String) async -> Bool {
        guard let url = URL(string: playlistURL) else {
            print("[MediaSave] Invalid playlist URL: \(playlistURL)")
            return false
        }

        // pathComponents: ["/", "watch", "{did}", "{cid}", "playlist.m3u8"]
        let parts = url.pathComponents
        guard parts.count >= 5 else {
            print("[MediaSave] Unexpected URL format: \(playlistURL)")
            return false
        }
        let did = parts[2]
        let cid = parts[3]
        print("[MediaSave] DID: \(did), CID: \(cid)")

        // DID を解決して PDS URL を取得
        guard let pdsURL = await resolvePDS(did: did) else {
            print("[MediaSave] Failed to resolve PDS for: \(did)")
            return false
        }
        print("[MediaSave] PDS: \(pdsURL)")

        // com.atproto.sync.getBlob でオリジナル動画ファイルを取得
        let encodedDID = did.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? did
        guard let blobURL = URL(string: "\(pdsURL)/xrpc/com.atproto.sync.getBlob?did=\(encodedDID)&cid=\(cid)"),
              let (data, response) = try? await URLSession.shared.data(from: blobURL),
              (response as? HTTPURLResponse)?.statusCode == 200,
              !data.isEmpty else {
            print("[MediaSave] Blob download failed")
            return false
        }
        print("[MediaSave] Blob downloaded: \(data.count) bytes")

        // 一時ファイルに書き込む
        let ext = videoExtension(from: response)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        guard (try? data.write(to: tempURL)) != nil else {
            print("[MediaSave] Failed to write temp file")
            return false
        }

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempURL)
            }, completionHandler: { success, error in
                if let error = error {
                    print("[MediaSave] Video performChanges error: \(error.localizedDescription)")
                }
                continuation.resume(returning: success)
            })
        }

        try? FileManager.default.removeItem(at: tempURL)
        return result
    }

    /// DID ドキュメントを解決して PDS URL を返す
    private static func resolvePDS(did: String) async -> String? {
        if did.hasPrefix("did:plc:") {
            // plc.directory で DID ドキュメントを取得
            guard let url = URL(string: "https://plc.directory/\(did)"),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let services = json["service"] as? [[String: Any]] else { return nil }
            for svc in services {
                if (svc["type"] as? String) == "AtprotoPersonalDataServer",
                   let endpoint = svc["serviceEndpoint"] as? String {
                    return endpoint
                }
            }
        } else if did.hasPrefix("did:web:") {
            let host = String(did.dropFirst("did:web:".count))
            return "https://\(host)"
        }
        return nil
    }

    /// レスポンスの Content-Type から動画ファイル拡張子を決定する
    private static func videoExtension(from response: URLResponse) -> String {
        let ct = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        if ct.contains("quicktime") { return "mov" }
        return "mp4"
    }
}
