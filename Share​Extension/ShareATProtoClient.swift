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
        via: String?
    ) async throws -> CreateRecordResponse {
        let did = currentSession.did

        let embed: PostEmbedCreate?
        if let images, !images.isEmpty {
            let imageEmbed = ImageEmbedCreate(images: images.map { ImageEmbedItem(image: $0.blob, alt: $0.alt, aspectRatio: nil) })
            embed = .images(imageEmbed)
        } else {
            embed = nil
        }

        let record = PostRecordCreate(text: text, facets: facets, replyRef: nil, embed: embed, via: via)
        let body = CreateRecordRequest(repo: did, collection: "app.bsky.feed.post", record: record)
        return try await post(nsid: "com.atproto.repo.createRecord", body: body)
    }

    // MARK: - 画像アップロード

    func uploadImage(data: Data, mimeType: String) async throws -> BlobRef {
        let session = try await ensureFreshSession()
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

    // MARK: - XRPC POST

    private func post<B: Encodable, R: Decodable>(nsid: String, body: B) async throws -> R {
        let session = try await ensureFreshSession()
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
            // トークンリフレッシュを試みる
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

    private func ensureFreshSession() async throws -> Session {
        return currentSession
    }

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

// MARK: - RichText Facet 自動検出

extension ShareATProtoClient {
    /// テキストから URL Facet を自動検出する簡易版
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
