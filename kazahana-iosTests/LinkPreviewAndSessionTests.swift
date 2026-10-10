//
//  LinkPreviewAndSessionTests.swift
//  kazahana-iosTests
//

import Foundation
import Testing
@testable import kazahana

@MainActor
struct StandardSiteURITests {

    @Test func relとhrefの順序や引用符に関わらず抽出する() {
        let html = """
        <head>
          <link rel="site.standard.publication" href="at://did:plc:a/site.standard.publication/1">
          <link href='at://did:plc:a/site.standard.document/2' rel='site.standard.document'>
        </head>
        """
        #expect(Set(LinkPreviewService.extractStandardSiteURIs(from: html)) == [
            "at://did:plc:a/site.standard.publication/1",
            "at://did:plc:a/site.standard.document/2",
        ])
    }

    @Test func at以外のhrefや関係のないlinkは無視する() {
        let html = """
        <link rel="site.standard.publication" href="https://example.com">
        <link rel="stylesheet" href="at://did:plc:a/x/1">
        """
        #expect(LinkPreviewService.extractStandardSiteURIs(from: html).isEmpty)
    }

    @Test func 同じURIは1つにまとめる() {
        let tag = #"<link rel="site.standard.publication" href="at://did:plc:a/p/1">"#
        #expect(LinkPreviewService.extractStandardSiteURIs(from: tag + tag) == ["at://did:plc:a/p/1"])
    }
}

@MainActor
struct DetectEncodingTests {

    private let url = URL(string: "https://example.com")!

    private func response(contentType: String?) -> URLResponse {
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                        headerFields: contentType.map { ["Content-Type": $0] })!
    }

    /// Shift_JIS の日本語を判定結果のエンコーディングで読めるか
    /// （CoreFoundation 経由の Shift_JIS は String.Encoding.shiftJIS と raw 値が異なるため、値ではなく読めるかで確かめる）
    private func decodesShiftJIS(_ encoding: String.Encoding) -> Bool {
        let sjis = Data([0x93, 0xFA, 0x96, 0x7B, 0x8C, 0xEA])  // "日本語"
        return String(data: sjis, encoding: encoding) == "日本語"
    }

    @Test func ヘッダのcharsetを優先する() {
        let data = Data(#"<meta charset="utf-8">"#.utf8)
        let encoding = LinkPreviewService.detectEncoding(response: response(contentType: "text/html; charset=Shift_JIS"), data: data)
        #expect(encoding != .utf8)
        #expect(decodesShiftJIS(encoding))
    }

    @Test func ヘッダになければmetaのcharsetを使う() {
        let data = Data(#"<html><head><meta charset="EUC-JP"></head>"#.utf8)
        #expect(LinkPreviewService.detectEncoding(response: response(contentType: "text/html"), data: data) == .japaneseEUC)
    }

    @Test func httpequivのcontenttypeから読む() {
        let data = Data(#"<meta http-equiv="Content-Type" content="text/html; charset=Shift_JIS">"#.utf8)
        #expect(decodesShiftJIS(LinkPreviewService.detectEncoding(response: response(contentType: nil), data: data)))
    }

    @Test func 手がかりがなければUTF8() {
        let plain = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        #expect(LinkPreviewService.detectEncoding(response: plain, data: Data("<html></html>".utf8)) == .utf8)
    }

    @Test func 先頭4096バイトより後ろのmetaは見ない() {
        let data = Data((String(repeating: " ", count: 5000) + #"<meta charset="Shift_JIS">"#).utf8)
        #expect(LinkPreviewService.detectEncoding(response: response(contentType: nil), data: data) == .utf8)
    }
}

@MainActor
struct SessionTests {

    private func sessionResponse(didDoc: String?) throws -> SessionResponse {
        try decode(SessionResponse.self, """
        {
          "did": "did:plc:me", "handle": "me.example", "accessJwt": "a", "refreshJwt": "r"
          \(didDoc.map { ", \"didDoc\": \($0)" } ?? "")
        }
        """)
    }

    @Test func DIDドキュメントのPDSを優先する() throws {
        let response = try sessionResponse(didDoc: """
        { "id": "did:plc:me", "service": [
          { "id": "#other", "type": "Other", "serviceEndpoint": "https://other.example" },
          { "id": "#atproto_pds", "type": "AtprotoPersonalDataServer", "serviceEndpoint": "https://pds.example" }
        ] }
        """)
        #expect(response.toSession(pdsHost: "https://bsky.social").pdsHost == "https://pds.example")
    }

    @Test func DIDドキュメントがなければ指定のホストを使う() throws {
        let session = try sessionResponse(didDoc: nil).toSession(pdsHost: "https://fallback.example")
        #expect(session == Session(did: "did:plc:me", handle: "me.example", accessJwt: "a",
                                   refreshJwt: "r", pdsHost: "https://fallback.example"))
    }

    @Test func PDSの指定がなければ指定のホストを使う() throws {
        let response = try sessionResponse(didDoc: #"{ "id": "did:plc:me", "service": [] }"#)
        #expect(response.toSession(pdsHost: "https://fallback.example").pdsHost == "https://fallback.example")
    }
}
