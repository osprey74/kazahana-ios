// AuthService.swift
// kazahana-ios
// 認証サービス（ログイン・ログアウト・PDS解決）

import Foundation

final class AuthService {

    private let client: ATProtoClient
    private let decoder = JSONDecoder()

    init(client: ATProtoClient) {
        self.client = client
        // AT Protocol は camelCase を使うため変換不要
    }

    // MARK: - ログイン

    /// ハンドル + アプリパスワードでログイン
    /// - Parameters:
    ///   - identifier: ハンドル（例: alice.bsky.social）または DID
    ///   - password: アプリパスワード
    /// - Returns: Session
    func login(identifier: String, password: String) async throws -> Session {
        // PDS ホストを解決（標準ユーザーは bsky.social、カスタムPDSは要解決）
        let pdsHost = try await resolvePDSHost(for: identifier)

        let body = CreateSessionRequest(identifier: identifier, password: password)
        let url = URL(string: "\(pdsHost)/xrpc/com.atproto.server.createSession")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("kazahana-ios/1.0", forHTTPHeaderField: "User-Agent")

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ATProtoError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorResponse = try? decoder.decode(ATProtoErrorResponse.self, from: data) {
                throw ATProtoError.apiError(code: errorResponse.error, message: errorResponse.message)
            }
            throw ATProtoError.httpError(statusCode: httpResponse.statusCode)
        }

        let sessionResponse = try decoder.decode(SessionResponse.self, from: data)
        let session = sessionResponse.toSession(pdsHost: pdsHost)
        client.updateSession(session)
        return session
    }

    // MARK: - ログアウト

    func logout() async {
        // deleteSession はベストエフォート（失敗しても Keychain は消す）
        if let session = client.currentSession {
            let url = URL(string: "\(session.pdsHost)/xrpc/com.atproto.server.deleteSession")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(session.refreshJwt)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)
        }
        client.updateSession(nil)
    }

    // MARK: - PDS ホスト解決

    /// ハンドルまたは DID から PDS ホストを解決する
    private func resolvePDSHost(for identifier: String) async throws -> String {
        // DID が直接指定された場合
        if identifier.hasPrefix("did:") {
            return try await resolveFromDID(identifier)
        }

        // ハンドルの場合: まず .well-known を試み、失敗したら bsky.social をデフォルトとする
        // bsky.social ホストのユーザーは通常 bsky.social が PDS
        // カスタムドメインの場合は DID を経由して解決する
        let handle = identifier.hasPrefix("@") ? String(identifier.dropFirst()) : identifier

        // .well-known/atproto-did からDIDを取得
        if let did = try? await fetchDIDFromWellKnown(handle: handle) {
            if let host = try? await resolveFromDID(did) {
                return host
            }
        }

        // フォールバック: bsky.social
        return "https://bsky.social"
    }

    private func fetchDIDFromWellKnown(handle: String) async throws -> String? {
        let url = URL(string: "https://\(handle)/.well-known/atproto-did")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let did = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              did.hasPrefix("did:") else {
            return nil
        }
        return did
    }

    private func resolveFromDID(_ did: String) async throws -> String {
        // did:plc は plc.directory から解決
        let docURL: URL
        if did.hasPrefix("did:plc:") {
            docURL = URL(string: "https://plc.directory/\(did)")!
        } else if did.hasPrefix("did:web:") {
            let host = did.dropFirst("did:web:".count)
            docURL = URL(string: "https://\(host)/.well-known/did.json")!
        } else {
            return "https://bsky.social"
        }

        let (data, response) = try await URLSession.shared.data(from: docURL)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return "https://bsky.social"
        }

        let decoder = JSONDecoder()
        guard let didDoc = try? decoder.decode(DIDDocument.self, from: data),
              let endpoint = didDoc.pdsEndpoint else {
            return "https://bsky.social"
        }
        return endpoint
    }
}

// MARK: - Request Body

private struct CreateSessionRequest: Encodable {
    let identifier: String
    let password: String
}


