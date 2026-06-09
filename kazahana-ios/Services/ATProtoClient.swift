// ATProtoClient.swift
// kazahana-ios
// AT Protocol XRPC HTTPクライアント
// 認証ヘッダー自動付与・トークン自動リフレッシュ・レート制限ハンドリングを担う

import Foundation

/// XRPC リクエストの基底クライアント
final class ATProtoClient {

    // MARK: - Properties

    private let sessionStore: SessionStore
    private(set) var _currentSession: Session?

    // currentSession への公開アクセサ
    var currentSession: Session? { _currentSession }

    /// セッション更新時のコールバック（ViewModel などが監視）
    var onSessionUpdated: ((Session?) -> Void)?

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let encoder: JSONEncoder = JSONEncoder()

    // MARK: - Init

    init(sessionStore: SessionStore) {
        self.sessionStore = sessionStore
        self._currentSession = sessionStore.load()
    }

    // MARK: - Session Management

    func updateSession(_ session: Session?) {
        _currentSession = session
        if let session {
            try? sessionStore.save(session)
        } else {
            sessionStore.delete()
        }
        onSessionUpdated?(session)
    }

    // MARK: - Public Request Methods

    /// GET リクエスト（Query）
    func get<T: Decodable>(
        nsid: String,
        params: [String: String] = [:],
        authenticated: Bool = true
    ) async throws -> T {
        let host = currentSession?.pdsHost ?? "https://bsky.social"
        var components = URLComponents(string: "\(host)/xrpc/\(nsid)")!
        if !params.isEmpty {
            components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        let request = try buildRequest(url: components.url!, method: "GET", authenticated: authenticated)
        return try await perform(request: request)
    }

    /// com.atproto.repo.getRecord — 単一レコードを取得する
    func getRecord(repo: String, collection: String, rkey: String) async throws -> GetRecordResponse {
        return try await get(
            nsid: "com.atproto.repo.getRecord",
            params: ["repo": repo, "collection": collection, "rkey": rkey]
        )
    }

    /// GET リクエスト（配列パラメータ対応）
    func getWithArrayParams<T: Decodable>(
        nsid: String,
        queryItems: [URLQueryItem],
        authenticated: Bool = true
    ) async throws -> T {
        let host = currentSession?.pdsHost ?? "https://bsky.social"
        var components = URLComponents(string: "\(host)/xrpc/\(nsid)")!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        let request = try buildRequest(url: components.url!, method: "GET", authenticated: authenticated)
        return try await perform(request: request)
    }

    /// POST リクエスト（Procedure）
    func post<Body: Encodable, Response: Decodable>(
        nsid: String,
        body: Body,
        host: String? = nil,
        useRefreshToken: Bool = false
    ) async throws -> Response {
        let targetHost = host ?? currentSession?.pdsHost ?? "https://bsky.social"
        let url = URL(string: "\(targetHost)/xrpc/\(nsid)")!
        let bodyData = try encoder.encode(body)
        var request = try buildRequest(url: url, method: "POST", authenticated: true, useRefreshToken: useRefreshToken)
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await perform(request: request)
    }

    /// バイナリデータのアップロード（uploadBlob）
    func uploadBlob(data: Data, mimeType: String) async throws -> UploadBlobResponse {
        let host = currentSession?.pdsHost ?? "https://bsky.social"
        let url = URL(string: "\(host)/xrpc/com.atproto.repo.uploadBlob")!
        var request = try buildRequest(url: url, method: "POST", authenticated: true)
        request.httpBody = data
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        return try await perform(request: request)
    }

    /// 動画アップロード制限を取得（app.bsky.video.getUploadLimits）
    func getVideoUploadLimits() async throws -> VideoUploadLimits {
        let host = currentSession?.pdsHost ?? "https://bsky.social"
        let url = URL(string: "\(host)/xrpc/app.bsky.video.getUploadLimits")!
        let request = try buildRequest(url: url, method: "GET", authenticated: true)
        return try await perform(request: request)
    }

    /// サービス認証トークンを取得（動画アップロード用）
    /// - Parameters:
    ///   - aud: 対象サービスの DID（PDS の did:web:<domain>）
    ///   - lxm: 許可する Lexicon メソッド
    ///   - expSecs: トークン有効期限（秒）
    func getServiceAuth(aud: String, lxm: String, expSecs: Int = 1800) async throws -> String {
        let host = currentSession?.pdsHost ?? "https://bsky.social"
        let exp = Int(Date().timeIntervalSince1970) + expSecs
        let params = ["aud": aud, "lxm": lxm, "exp": "\(exp)"]
        struct ServiceAuthResponse: Decodable { let token: String }
        var components = URLComponents(string: "\(host)/xrpc/com.atproto.server.getServiceAuth")!
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        let request = try buildRequest(url: components.url!, method: "GET", authenticated: true)
        let response: ServiceAuthResponse = try await perform(request: request)
        return response.token
    }

    /// 動画を video.bsky.app 経由でアップロードし、ジョブIDを返す
    /// - Parameters:
    ///   - data: 動画バイナリ
    ///   - mimeType: 動画の MIME タイプ（video/mp4 または video/quicktime）
    ///   - fileName: ファイル名（拡張子付き）
    ///   - serviceToken: getServiceAuth で取得したトークン
    func uploadVideoToService(data: Data, mimeType: String, fileName: String, serviceToken: String) async throws -> VideoUploadJobStatus {
        guard let did = currentSession?.did else { throw ATProtoError.unauthorized }
        var components = URLComponents(string: "https://video.bsky.app/xrpc/app.bsky.video.uploadVideo")!
        components.queryItems = [
            URLQueryItem(name: "did", value: did),
            URLQueryItem(name: "name", value: fileName)
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(serviceToken)", forHTTPHeaderField: "Authorization")
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? decoder.decode(ATProtoErrorResponse.self, from: responseData) {
                throw ATProtoError.apiError(code: errorResponse.error, message: errorResponse.message)
            }
            throw ATProtoError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        // レスポンスは { jobStatus: { ... } } でラップされている場合がある
        if let wrapped = try? decoder.decode(VideoJobStatusWrapper.self, from: responseData) {
            return wrapped.jobStatus
        }
        return try decoder.decode(VideoUploadJobStatus.self, from: responseData)
    }

    /// 動画処理ジョブのステータスをポーリング
    func getVideoJobStatus(jobId: String, serviceToken: String) async throws -> VideoUploadJobStatus {
        var components = URLComponents(string: "https://video.bsky.app/xrpc/app.bsky.video.getJobStatus")!
        components.queryItems = [URLQueryItem(name: "jobId", value: jobId)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(serviceToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (responseData, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(statusCode) else {
            throw ATProtoError.httpError(statusCode: statusCode)
        }
        if let wrapped = try? decoder.decode(VideoJobStatusWrapper.self, from: responseData) {
            return wrapped.jobStatus
        }
        return try decoder.decode(VideoUploadJobStatus.self, from: responseData)
    }

    /// GET リクエスト（atproto-proxy ヘッダー付き）
    func getWithProxy<T: Decodable>(
        nsid: String,
        params: [String: String] = [:],
        proxyHeader: String = "did:web:api.bsky.chat#bsky_chat"
    ) async throws -> T {
        let host = currentSession?.pdsHost ?? "https://bsky.social"
        var components = URLComponents(string: "\(host)/xrpc/\(nsid)")!
        if !params.isEmpty {
            components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = try buildRequest(url: components.url!, method: "GET", authenticated: true)
        request.setValue(proxyHeader, forHTTPHeaderField: "atproto-proxy")
        return try await perform(request: request)
    }

    /// POST リクエスト（atproto-proxy ヘッダー付き）
    func postWithProxy<Body: Encodable, Response: Decodable>(
        nsid: String,
        body: Body,
        proxyHeader: String = "did:web:api.bsky.chat#bsky_chat"
    ) async throws -> Response {
        let host = currentSession?.pdsHost ?? "https://bsky.social"
        let url = URL(string: "\(host)/xrpc/\(nsid)")!
        let bodyData = try encoder.encode(body)
        var request = try buildRequest(url: url, method: "POST", authenticated: true)
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(proxyHeader, forHTTPHeaderField: "atproto-proxy")
        return try await perform(request: request)
    }

    /// GET リクエスト（配列パラメータ + atproto-proxy ヘッダー付き）
    func getWithProxyArrayParams<T: Decodable>(
        nsid: String,
        queryItems: [URLQueryItem],
        proxyHeader: String = "did:web:api.bsky.chat#bsky_chat"
    ) async throws -> T {
        let host = currentSession?.pdsHost ?? "https://bsky.social"
        var components = URLComponents(string: "\(host)/xrpc/\(nsid)")!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        var request = try buildRequest(url: components.url!, method: "GET", authenticated: true)
        request.setValue(proxyHeader, forHTTPHeaderField: "atproto-proxy")
        return try await perform(request: request)
    }

    /// ボディなし POST
    func postEmpty<Response: Decodable>(
        nsid: String,
        useRefreshToken: Bool = false
    ) async throws -> Response {
        let host = currentSession?.pdsHost ?? "https://bsky.social"
        let url = URL(string: "\(host)/xrpc/\(nsid)")!
        let request = try buildRequest(url: url, method: "POST", authenticated: true, useRefreshToken: useRefreshToken)
        return try await perform(request: request)
    }

    // MARK: - Private Helpers

    private func buildRequest(
        url: URL,
        method: String,
        authenticated: Bool,
        useRefreshToken: Bool = false
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("kazahana-ios/1.0", forHTTPHeaderField: "User-Agent")

        if authenticated {
            let token = useRefreshToken ? currentSession?.refreshJwt : currentSession?.accessJwt
            if let token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }
        return request
    }

    /// リクエスト実行（401 時に自動リフレッシュ＋リトライ、429 時にバックオフ）
    private func perform<T: Decodable>(request: URLRequest, retryCount: Int = 0) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ATProtoError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            do {
                let decodeData = data.isEmpty ? Data("{}".utf8) : data
                return try decoder.decode(T.self, from: decodeData)
            } catch {
                // デバッグ用: どのフィールドで失敗したかを出力
                print("[ATProto] Decode error for \(T.self): \(error)")
                if let json = try? JSONSerialization.jsonObject(with: data),
                   let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
                   let str = String(data: pretty, encoding: .utf8) {
                    print("[ATProto] Response JSON (first 2000 chars):\n\(str.prefix(2000))")
                }
                throw ATProtoError.decodingFailed(error)
            }

        case 401:
            // トークンリフレッシュを試みる（無限ループ防止のため1回のみ）
            guard retryCount == 0 else {
                updateSession(nil)
                throw ATProtoError.unauthorized
            }
            try await refreshToken()
            // 新しいトークンで再リクエスト
            var retryRequest = request
            if let newToken = currentSession?.accessJwt {
                retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            }
            return try await perform(request: retryRequest, retryCount: retryCount + 1)

        case 429:
            // レート制限: retry-after ヘッダーを参照してバックオフ
            guard retryCount < 3 else {
                throw ATProtoError.rateLimited
            }
            let retryAfter = httpResponse.value(forHTTPHeaderField: "retry-after")
                .flatMap { Double($0) } ?? pow(2.0, Double(retryCount + 1))
            try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
            return try await perform(request: request, retryCount: retryCount + 1)

        default:
            // AT Protocol エラーレスポンスをパース
            if let errorResponse = try? decoder.decode(ATProtoErrorResponse.self, from: data) {
                // Bluesky は期限切れアクセストークンに 400 ExpiredToken を返す場合がある
                // 401 と同様にリフレッシュして再試行する
                if errorResponse.error == "ExpiredToken", retryCount == 0 {
                    try await refreshToken()
                    var retryRequest = request
                    if let newToken = currentSession?.accessJwt {
                        retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                    }
                    return try await perform(request: retryRequest, retryCount: retryCount + 1)
                }
                throw ATProtoError.apiError(code: errorResponse.error, message: errorResponse.message)
            }
            throw ATProtoError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    // MARK: - Token Refresh

    /// 外部から呼び出し可能なトークンリフレッシュ（起動時など）
    func refreshSessionPublic() async throws {
        try await refreshToken()
    }

    private func refreshToken() async throws {
        guard let session = currentSession else {
            throw ATProtoError.unauthorized
        }
        let url = URL(string: "\(session.pdsHost)/xrpc/com.atproto.server.refreshSession")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.refreshJwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            updateSession(nil)
            throw ATProtoError.unauthorized
        }

        let newSessionResponse = try decoder.decode(SessionResponse.self, from: data)
        let newSession = newSessionResponse.toSession(pdsHost: session.pdsHost)
        updateSession(newSession)
    }
}

// MARK: - Error Types

enum ATProtoError: LocalizedError {
    case invalidResponse
    case decodingFailed(Error)
    case unauthorized
    case rateLimited
    case httpError(statusCode: Int)
    case apiError(code: String, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "無効なレスポンスです"
        case .decodingFailed(let error):
            return "データの解析に失敗しました: \(error.localizedDescription)"
        case .unauthorized:
            return "認証が必要です。再度ログインしてください"
        case .rateLimited:
            return "リクエストが多すぎます。しばらくお待ちください"
        case .httpError(let code):
            return "HTTPエラー: \(code)"
        case .apiError(let code, let message):
            return message ?? "APIエラー: \(code)"
        }
    }
}

struct ATProtoErrorResponse: Codable {
    let error: String
    let message: String?
}
