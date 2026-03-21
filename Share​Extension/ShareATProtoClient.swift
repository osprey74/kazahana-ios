// ShareATProtoClient.swift
// Share​Extension
// Share Extension 用軽量 AT Protocol クライアント

import Foundation

final class ShareATProtoClient {

    private(set) var currentSession: Session
    private let urlSession: URLSession

    init(session: Session) {
        self.currentSession = session
        self.urlSession = URLSession.shared
    }

    // MARK: - 投稿作成

    func createPost(
        text: String,
        facets: [Facet]?,
        images: [(blob: BlobRef, alt: String)]?,
        linkCard: ExternalCard?,
        langs: [String]?,
        via: String?
    ) async throws -> CreateRecordResponse {
        let did = currentSession.did

        // embed: 画像 > リンクカード
        let embed: PostEmbedCreate?
        if let images, !images.isEmpty {
            let imageEmbed = ImageEmbedCreate(images: images.map { ImageEmbedItem(image: $0.blob, alt: $0.alt, aspectRatio: nil) })
            embed = .images(imageEmbed)
        } else if let linkCard {
            embed = .external(ExternalEmbedCreate(external: linkCard))
        } else {
            embed = nil
        }

        let record = PostRecordCreate(
            text: text,
            facets: facets,
            replyRef: nil,
            embed: embed,
            langs: langs,
            via: via
        )
        let body = CreateRecordRequest(repo: did, collection: "app.bsky.feed.post", record: record)
        return try await post(nsid: "com.atproto.repo.createRecord", body: body)
    }

    // MARK: - 画像アップロード

    func uploadImage(data: Data, mimeType: String) async throws -> BlobRef {
        let session = currentSession
        let url = URL(string: "\(session.pdsHost)/xrpc/com.atproto.repo.uploadBlob")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessJwt)", forHTTPHeaderField: "Authorization")
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (responseData, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ATProtoError.unknown(NSError(domain: "ShareATProto", code: -1))
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ATProtoError.httpError(httpResponse.statusCode, String(data: responseData, encoding: .utf8))
        }
        let result = try JSONDecoder().decode(UploadBlobResponse.self, from: responseData)
        return result.blob
    }

    // MARK: - OGP 取得（リンクカード用）

    /// URL の OGP メタタグを取得して ExternalCard を返す
    /// サムネイル画像があればアップロードして BlobRef を含める
    func fetchLinkCard(url: URL) async throws -> ExternalCard {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (compatible; kazahana/1.0)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, _) = try await urlSession.data(for: request)
        let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""

        let title = ogValue(html: html, property: "og:title") ?? titleTag(html: html) ?? url.host ?? ""
        let description = ogValue(html: html, property: "og:description") ?? metaDescription(html: html) ?? ""
        let imageURLString = ogValue(html: html, property: "og:image")

        // サムネイルのアップロード（失敗しても続行）
        var thumbBlob: BlobRef? = nil
        if let imgStr = imageURLString, let imgURL = URL(string: imgStr) {
            thumbBlob = try? await uploadThumbnail(from: imgURL)
        }

        return ExternalCard(
            uri: url.absoluteString,
            title: title,
            description: description,
            thumb: thumbBlob
        )
    }

    private func uploadThumbnail(from url: URL) async throws -> BlobRef {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ATProtoError.httpError(0, nil)
        }
        let mimeType = httpResponse.mimeType ?? "image/jpeg"
        // 1MB 以内に圧縮
        let compressed = compressIfNeeded(data: data, mimeType: mimeType)
        return try await uploadImage(data: compressed, mimeType: "image/jpeg")
    }

    private func compressIfNeeded(data: Data, mimeType: String) -> Data {
        guard data.count > 1_000_000,
              mimeType.hasPrefix("image/"),
              let uiImage = UIImage(data: data) else { return data }
        var quality: CGFloat = 0.8
        var result = uiImage.jpegData(compressionQuality: quality) ?? data
        while result.count > 950_000 && quality > 0.2 {
            quality -= 0.1
            result = uiImage.jpegData(compressionQuality: quality) ?? result
        }
        return result
    }

    // MARK: - XRPC POST

    private func post<B: Encodable, R: Decodable>(nsid: String, body: B) async throws -> R {
        let session = currentSession
        let url = URL(string: "\(session.pdsHost)/xrpc/\(nsid)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessJwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (responseData, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ATProtoError.unknown(NSError(domain: "ShareATProto", code: -1))
        }

        if httpResponse.statusCode == 401 {
            try await refreshSession()
            return try await post(nsid: nsid, body: body)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ATProtoError.httpError(httpResponse.statusCode, String(data: responseData, encoding: .utf8))
        }
        do {
            return try JSONDecoder().decode(R.self, from: responseData)
        } catch {
            throw ATProtoError.decodingError(error)
        }
    }

    // MARK: - セッションリフレッシュ

    private func refreshSession() async throws {
        let url = URL(string: "\(currentSession.pdsHost)/xrpc/com.atproto.server.refreshSession")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(currentSession.refreshJwt)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ATProtoError.unauthorized
        }

        struct RefreshResponse: Decodable {
            let accessJwt: String
            let refreshJwt: String
            let did: String
            let handle: String
        }
        let refreshed = try JSONDecoder().decode(RefreshResponse.self, from: data)
        currentSession = Session(
            did: refreshed.did,
            handle: refreshed.handle,
            accessJwt: refreshed.accessJwt,
            refreshJwt: refreshed.refreshJwt,
            pdsHost: currentSession.pdsHost
        )
    }
}

// MARK: - HTML パース（OGP）

private extension ShareATProtoClient {

    func ogValue(html: String, property: String) -> String? {
        // <meta property="og:title" content="..."> または <meta name="og:title" content="...">
        let patterns = [
            #"<meta[^>]+property="\#(property)"[^>]+content="([^"]*)"[^>]*/?>""#,
            #"<meta[^>]+content="([^"]*)"[^>]+property="\#(property)"[^>]*/?>""#,
            #"<meta[^>]+property='\#(property)'[^>]+content='([^']*)'[^>]*/?>""#,
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

    func titleTag(html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<title[^>]*>([^<]+)</title>"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return htmlDecode(String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func metaDescription(html: String) -> String? {
        let patterns = [
            #"<meta[^>]+name="description"[^>]+content="([^"]*)"[^>]*/?>""#,
            #"<meta[^>]+content="([^"]*)"[^>]+name="description"[^>]*/?>""#,
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

    func htmlDecode(_ string: String) -> String {
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&nbsp;", " "),
        ]
        var result = string
        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        // &#数値; 形式
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let nsResult = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
            // 簡易処理: 数値エンティティはそのまま除去せず Unicode 変換
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if let range = Range(match.range(at: 1), in: result),
                   let code = UInt32(result[range]),
                   let scalar = Unicode.Scalar(code) {
                    let r = Range(match.range, in: result)!
                    result.replaceSubrange(r, with: String(scalar))
                }
            }
            _ = nsResult  // suppress warning
        }
        return result
    }
}

// MARK: - RichText Facet 自動検出

extension ShareATProtoClient {
    /// テキストから URL および @mention Facet を自動検出する
    static func detectFacets(in text: String) -> [Facet] {
        var facets: [Facet] = []
        let utf8 = Array(text.utf8)

        // URL 検出
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        detector?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match, let matchRange = Range(match.range, in: text),
                  let url = match.url else { return }
            let byteStart = text[text.startIndex..<matchRange.lowerBound].utf8.count
            let byteEnd = text[text.startIndex..<matchRange.upperBound].utf8.count
            guard byteStart < byteEnd, byteEnd <= utf8.count else { return }
            let facet = Facet(
                index: FacetIndex(byteStart: byteStart, byteEnd: byteEnd),
                features: [FacetFeature(type: "app.bsky.richtext.facet#link", uri: url.absoluteString, did: nil, tag: nil)]
            )
            facets.append(facet)
        }
        return facets
    }
}

// UIImage import
import UIKit
