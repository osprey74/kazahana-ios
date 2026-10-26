//
//  DeepLinkTests.swift
//  kazahana-iosTests
//

import Foundation
import Testing
@testable import kazahana

@MainActor
struct DeepLinkPostURITests {

    private let uri = "at://did:plc:heztswuhu24kudwdaz7y4bi3/app.bsky.feed.post/3mxuo6d2pg725"

    @Test func エンコード済みのAT_URIを復元する() throws {
        let encoded = try #require(uri.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        let url = try #require(URL(string: "kazahana://post/\(encoded)"))
        #expect(MainTabView.postURI(fromDeepLink: url) == uri)
    }

    @Test func 未エンコードのAT_URIもそのまま受け付ける() throws {
        let url = try #require(URL(string: "kazahana://post/\(uri)"))
        #expect(MainTabView.postURI(fromDeepLink: url) == uri)
    }

    @Test func AT_URIでなければnil() throws {
        #expect(MainTabView.postURI(fromDeepLink: try #require(URL(string: "kazahana://post/"))) == nil)
        #expect(MainTabView.postURI(fromDeepLink: try #require(URL(string: "kazahana://post/https%3A%2F%2Fexample.com"))) == nil)
    }
}
