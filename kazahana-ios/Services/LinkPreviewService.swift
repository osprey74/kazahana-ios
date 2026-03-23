// LinkPreviewService.swift
// kazahana-ios
// URL から OGP メタデータを取得し、リンクカード用データを生成するサービス

import Foundation
import UIKit

/// リンクプレビュー表示用の中間データ（UI 表示 + 投稿送信の両方で使用）
struct LinkPreview {
    let url: URL
    let title: String
    let description: String
    var thumbImage: UIImage? = nil   // ローカル表示用サムネイル
    var thumbBlob: BlobRef? = nil    // アップロード済みサムネイル（投稿時に使用）
}

/// OGP 取得・サムネイルアップロードを担当するサービス
final class LinkPreviewService {

    private let client: ATProtoClient
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    init(client: ATProtoClient) {
        self.client = client
    }

    // MARK: - OGP 取得

    /// URL の OGP メタデータを取得して LinkPreview を返す
    /// サムネイルは UIImage としてのみ返す（アップロードは uploadThumbnail で別途行う）
    func fetchPreview(url: URL) async throws -> LinkPreview {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (compatible; kazahana/1.0)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, _) = try await urlSession.data(for: request)
        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""

        let title = ogValue(html: html, property: "og:title")
            ?? titleTag(html: html)
            ?? url.host
            ?? ""
        let description = ogValue(html: html, property: "og:description")
            ?? metaDescription(html: html)
            ?? ""
        let imageURLString = ogValue(html: html, property: "og:image")

        // サムネイル取得（失敗しても続行）
        var thumbImage: UIImage? = nil
        if let imgStr = imageURLString,
           let imgURL = URL(string: imgStr) ?? URL(string: imgStr, relativeTo: url)?.absoluteURL {
            thumbImage = try? await fetchThumbnailImage(from: imgURL)
        }

        return LinkPreview(
            url: url,
            title: title,
            description: description,
            thumbImage: thumbImage
        )
    }

    // MARK: - サムネイルアップロード

    /// サムネイル画像を Bluesky にアップロードして BlobRef を返す
    func uploadThumbnail(image: UIImage) async throws -> BlobRef {
        let compressed = compressImage(image)
        let response = try await client.uploadBlob(data: compressed, mimeType: "image/jpeg")
        return response.blob
    }

    // MARK: - Private

    private func fetchThumbnailImage(from url: URL) async throws -> UIImage {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let image = UIImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }
        return image
    }

    private func compressImage(_ image: UIImage) -> Data {
        // 最大 1MB に収まるよう圧縮
        let maxBytes = 950_000
        var quality: CGFloat = 0.85
        while quality >= 0.3 {
            if let data = image.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data
            }
            quality -= 0.1
        }
        return image.jpegData(compressionQuality: 0.2) ?? Data()
    }

    // MARK: - HTML パース

    private func ogValue(html: String, property: String) -> String? {
        let patterns = [
            #"<meta[^>]+property="\#(property)"[^>]+content="([^"]*)"[^>]*/?>"#,
            #"<meta[^>]+content="([^"]*)"[^>]+property="\#(property)"[^>]*/?>"#,
            #"<meta[^>]+property='\#(property)'[^>]+content='([^']*)'[^>]*/?>"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                return htmlDecode(String(html[range]))
            }
        }
        return nil
    }

    private func titleTag(html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<title[^>]*>([^<]+)</title>"#,
            options: .caseInsensitive
        ),
        let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
        let range = Range(match.range(at: 1), in: html) else { return nil }
        return htmlDecode(String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func metaDescription(html: String) -> String? {
        let patterns = [
            #"<meta[^>]+name="description"[^>]+content="([^"]*)"[^>]*/?>"#,
            #"<meta[^>]+content="([^"]*)"[^>]+name="description"[^>]*/?>"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                return htmlDecode(String(html[range]))
            }
        }
        return nil
    }

    private func htmlDecode(_ string: String) -> String {
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&nbsp;", " "), ("&mdash;", "—"), ("&ndash;", "–"),
            ("&laquo;", "«"), ("&raquo;", "»"),
        ]
        var result = string
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        // &#数字; 形式
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if let range = Range(match.range, in: result),
                   let codeRange = Range(match.range(at: 1), in: result),
                   let code = UInt32(result[codeRange]),
                   let scalar = Unicode.Scalar(code) {
                    result.replaceSubrange(range, with: String(Character(scalar)))
                }
            }
        }
        return result
    }
}

// MARK: - URL 検出ヘルパー

extension LinkPreviewService {

    /// テキスト中の最初の URL を検出して返す
    static func detectFirstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector.firstMatch(in: text, range: range),
              let url = match.url else { return nil }
        // http/https のみ対象
        guard let scheme = url.scheme, scheme == "http" || scheme == "https" else { return nil }
        return url
    }
}
