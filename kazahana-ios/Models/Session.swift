// Session.swift
// kazahana-ios
// Bluesky セッション情報モデル

import Foundation

/// Bluesky セッション情報
struct Session: Codable, Equatable {
    let did: String
    let handle: String
    let accessJwt: String
    let refreshJwt: String
    let pdsHost: String

    init(did: String, handle: String, accessJwt: String, refreshJwt: String, pdsHost: String = "https://bsky.social") {
        self.did = did
        self.handle = handle
        self.accessJwt = accessJwt
        self.refreshJwt = refreshJwt
        self.pdsHost = pdsHost
    }
}

/// createSession / refreshSession のレスポンス
struct SessionResponse: Codable {
    let did: String
    let handle: String
    let accessJwt: String
    let refreshJwt: String
    let didDoc: DIDDocument?
    let active: Bool?
    let status: String?

    func toSession(pdsHost: String) -> Session {
        // didDoc から PDS ホストを解決できる場合はそちらを優先
        let resolvedHost = didDoc?.pdsEndpoint ?? pdsHost
        return Session(
            did: did,
            handle: handle,
            accessJwt: accessJwt,
            refreshJwt: refreshJwt,
            pdsHost: resolvedHost
        )
    }
}

/// DID ドキュメント（PDS エンドポイント解決用）
struct DIDDocument: Codable {
    let id: String?
    let service: [DIDService]?

    var pdsEndpoint: String? {
        service?.first(where: { $0.id.hasSuffix("#atproto_pds") })?.serviceEndpoint
    }
}

struct DIDService: Codable {
    let id: String
    let type: String
    let serviceEndpoint: String
}
