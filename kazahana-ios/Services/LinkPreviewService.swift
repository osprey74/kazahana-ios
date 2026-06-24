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
    var associatedRefs: [StrongRef]? = nil  // Standard Site 関連参照（投稿時に使用）
    var externalView: ExternalView? = nil   // Standard Site 拡張プレビュー（コンポーザー表示用）
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

    // MARK: - プレビュー取得（Standard Site 対応）

    /// URL の OGP メタデータを取得して LinkPreview を返す
    /// Standard Site 対応 URL の場合は getEmbedExternalView XRPC を呼び出し、
    /// associatedRefs を含むリッチプレビューを返す
    func fetchPreview(url: URL) async throws -> LinkPreview {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (compatible; kazahana/1.0)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, response) = try await urlSession.data(for: request)
        let encoding = Self.detectEncoding(response: response, data: data)
        let html = String(data: data, encoding: encoding)
            ?? String(data: data, encoding: .utf8)
            ?? ""

        // Standard Site: AT-URI を抽出し、見つかれば XRPC で拡張プレビューを取得
        let standardSiteURIs = Self.extractStandardSiteURIs(from: html)
        if !standardSiteURIs.isEmpty {
            if let preview = try? await fetchStandardSitePreview(url: url, uris: standardSiteURIs) {
                return preview
            }
            // XRPC 失敗時は OGP にフォールバック
        }

        // 通常の OGP パース（Twitter Card をフォールバックとして使用）
        let title = ogValue(html: html, property: "og:title")
            ?? ogValue(html: html, property: "twitter:title")
            ?? titleTag(html: html)
            ?? url.host
            ?? ""
        let description = ogValue(html: html, property: "og:description")
            ?? ogValue(html: html, property: "twitter:description")
            ?? metaDescription(html: html)
            ?? ""
        let imageURLString = ogValue(html: html, property: "og:image")
            ?? ogValue(html: html, property: "twitter:image")

        // サムネイル取得（失敗しても続行）
        var thumbImage: UIImage? = nil
        if var imgStr = imageURLString {
            // プロトコル相対URL（//cdn.example.com/...）を https: に補完
            if imgStr.hasPrefix("//") {
                imgStr = "https:" + imgStr
            }
            if let imgURL = URL(string: imgStr) ?? URL(string: imgStr, relativeTo: url)?.absoluteURL {
                thumbImage = try? await fetchThumbnailImage(from: imgURL)
            }
        }

        return LinkPreview(
            url: url,
            title: title,
            description: description,
            thumbImage: thumbImage
        )
    }

    // MARK: - Standard Site

    /// HTML から Standard Site の AT-URI を抽出（<link rel="site.standard.*" href="at://...">）
    static func extractStandardSiteURIs(from html: String) -> [String] {
        var uris = Set<String>()
        guard let linkRegex = try? NSRegularExpression(
            pattern: #"<link\b[^>]*>"#, options: .caseInsensitive
        ) else { return [] }

        let matches = linkRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        for match in matches {
            guard let range = Range(match.range, in: html) else { continue }
            let tag = String(html[range])
            // rel="site.standard.*" を含むか
            guard tag.range(of: #"rel=["']site\.standard\.[a-z]+["']"#, options: .regularExpression, range: nil, locale: nil) != nil else { continue }
            // href="at://..." を抽出
            if let hrefMatch = tag.range(of: #"href=["'](at://[^"']+)["']"#, options: .regularExpression),
               let atURIMatch = tag[hrefMatch].range(of: #"at://[^"']+"#, options: .regularExpression) {
                uris.insert(String(tag[atURIMatch]))
            }
        }
        return Array(uris)
    }

    /// getEmbedExternalView XRPC を呼び出して Standard Site 拡張プレビューを取得
    private func fetchStandardSitePreview(url: URL, uris: [String]) async throws -> LinkPreview {
        var queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        for uri in uris {
            queryItems.append(URLQueryItem(name: "uris", value: uri))
        }

        let response: EmbedExternalViewResponse = try await client.getWithArrayParams(
            nsid: "app.bsky.embed.getEmbedExternalView",
            queryItems: queryItems
        )

        let ext = response.view.external
        // サムネイル取得（Standard Site URL は thumb が空の場合がある）
        var thumbImage: UIImage? = nil
        if let thumbStr = ext.thumb, let thumbURL = URL(string: thumbStr) {
            thumbImage = try? await fetchThumbnailImage(from: thumbURL)
        }

        return LinkPreview(
            url: url,
            title: ext.title,
            description: ext.description ?? "",
            thumbImage: thumbImage,
            associatedRefs: response.associatedRefs,
            externalView: ext
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

    // MARK: - 文字コード判定

    /// HTTP Content-Type ヘッダ → HTML meta charset → UTF-8 の優先度でエンコーディングを判定
    static func detectEncoding(response: URLResponse, data: Data) -> String.Encoding {
        // 1. HTTP Content-Type ヘッダの charset
        if let httpResponse = response as? HTTPURLResponse,
           let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
           let charsetName = Self.extractCharset(from: contentType) {
            if let encoding = Self.encoding(fromIANAName: charsetName) {
                return encoding
            }
        }

        // 2. HTML 先頭 4096 バイトから <meta charset="..."> を検出
        //    .isoLatin1 は全バイト値をマッピングするため、非 ASCII バイトを含むデータでも nil にならない
        let headBytes = data.prefix(4096)
        if let head = String(data: headBytes, encoding: .isoLatin1) {
            let metaPatterns = [
                #"<meta[^>]+charset\s*=\s*["']?([^"'>\s;]+)"#,
                #"<meta[^>]+http-equiv\s*=\s*["']?content-type[^>]*charset=([^"'>\s;]+)"#,
            ]
            for pattern in metaPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                   let match = regex.firstMatch(in: head, range: NSRange(head.startIndex..., in: head)),
                   let range = Range(match.range(at: 1), in: head) {
                    let charsetName = String(head[range])
                    if let encoding = Self.encoding(fromIANAName: charsetName) {
                        return encoding
                    }
                }
            }
        }

        // 3. デフォルト UTF-8
        return .utf8
    }

    /// Content-Type ヘッダ文字列から charset 値を抽出
    private static func extractCharset(from contentType: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"charset=([^\s;]+)"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: contentType, range: NSRange(contentType.startIndex..., in: contentType)),
              let range = Range(match.range(at: 1), in: contentType) else { return nil }
        return String(contentType[range])
    }

    /// IANA charset 名を String.Encoding に変換
    private static func encoding(fromIANAName name: String) -> String.Encoding? {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }

    // MARK: - HTML パース

    private func ogValue(html: String, property: String) -> String? {
        // property= と name= の両方に対応（サイトにより使い分けがある）
        let attrs = ["property", "name"]
        let quotes: [(String, String)] = [("\"", "\""), ("'", "'")]
        var patterns: [String] = []
        for attr in attrs {
            for (q, q2) in quotes {
                // attr → content の順
                patterns.append("<meta[^>]+\(attr)=\(q)\(property)\(q2)[^>]+content=\(q)([^\(q)]*)\(q2)[^>]*/?>")
                // content → attr の順
                patterns.append("<meta[^>]+content=\(q)([^\(q)]*)\(q2)[^>]+\(attr)=\(q)\(property)\(q2)[^>]*/?>")
            }
        }
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
            #"<meta[^>]+name='description'[^>]+content='([^']*)'[^>]*/?>"#,
            #"<meta[^>]+content='([^']*)'[^>]+name='description'[^>]*/?>"#,
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
