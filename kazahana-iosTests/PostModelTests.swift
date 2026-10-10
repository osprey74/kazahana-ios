//
//  PostModelTests.swift
//  kazahana-iosTests
//

import Foundation
import Testing
@testable import kazahana

@MainActor
struct TimelineResponseTests {

    @Test func 壊れた投稿だけを飛ばしてタイムラインを読み込む() throws {
        let json = """
        {
          "cursor": "next",
          "feed": [
            { "post": \(postViewJSON(uri: "at://a/1")) },
            { "post": { "uri": "at://broken" } },
            { "post": \(postViewJSON(uri: "at://a/2")) }
          ]
        }
        """
        let response = try decode(TimelineResponse.self, json)
        #expect(response.cursor == "next")
        #expect(response.feed.map(\.id) == ["at://a/1", "at://a/2"])
    }

    @Test func feedキーがなければ失敗する() {
        #expect(throws: (any Error).self) {
            try decode(TimelineResponse.self, #"{ "cursor": "x" }"#)
        }
    }

    @Test func SafeDecodableは失敗をnilにする() throws {
        let values = try decode([SafeDecodable<Int>].self, #"[1, "x", 3]"#)
        #expect(values.map(\.value) == [1, nil, 3])
    }
}

@MainActor
struct FeedViewPostTests {

    @Test func OPスレッドの位置を読み込む() throws {
        let json = #"{ "post": \#(postViewJSON()), "opThreadPostIndex": 2, "opThreadPostCount": 3 }"#
        let item = try decode(FeedViewPost.self, json)
        #expect(item.opThreadPostIndex == 2)
        #expect(item.opThreadPostCount == 3)
    }

    @Test func OPスレッドの位置がなければnil() throws {
        let item = try decode(FeedViewPost.self, #"{ "post": \#(postViewJSON()) }"#)
        #expect(item.opThreadPostIndex == nil)
        #expect(item.opThreadPostCount == nil)
    }

    @Test func 同じURIなら等しいとみなす() throws {
        let a = try decode(FeedViewPost.self, #"{ "post": \#(postViewJSON(uri: "at://same", text: "a")) }"#)
        let b = try decode(FeedViewPost.self, #"{ "post": \#(postViewJSON(uri: "at://same", text: "b")) }"#)
        #expect(a == b)
    }
}

@MainActor
struct PostRecordTests {

    @Test func viaはドル記号付きのキーから読む() throws {
        let record = try decode(PostRecord.self, #"{ "text": "hi", "$via": "kazahana for iOS", "tags": ["bsaf:v1"] }"#)
        #expect(record.via == "kazahana for iOS")
        #expect(record.tags == ["bsaf:v1"])
    }

    @Test func Facetを読み込む() throws {
        let json = """
        {
          "text": "@a",
          "facets": [{
            "index": { "byteStart": 0, "byteEnd": 2 },
            "features": [{ "$type": "app.bsky.richtext.facet#mention", "did": "did:plc:a" }]
          }]
        }
        """
        let record = try decode(PostRecord.self, json)
        let feature = try #require(record.facets?.first?.features.first)
        #expect(feature.type == "app.bsky.richtext.facet#mention")
        #expect(feature.did == "did:plc:a")
    }
}

@MainActor
struct PostEmbedTests {

    @Test func 画像を読み込む() throws {
        let json = #"{ "$type": "app.bsky.embed.images#view", "images": [{ "thumb": "t", "fullsize": "f", "alt": "a" }] }"#
        guard case .images(let embed) = try decode(PostEmbed.self, json) else {
            Issue.record("images として読み込まれていない")
            return
        }
        #expect(embed.images.first?.alt == "a")
    }

    @Test func 画像のaltがなければunknownにする() throws {
        let json = #"{ "$type": "app.bsky.embed.images#view", "images": [{ "thumb": "t", "fullsize": "f" }] }"#
        guard case .unknown = try decode(PostEmbed.self, json) else {
            Issue.record("unknown にフォールバックしていない")
            return
        }
    }

    @Test func ギャラリーはthumbnailをthumbに対応付ける() throws {
        let json = #"{ "$type": "app.bsky.embed.gallery#view", "items": [{ "thumbnail": "t", "fullsize": "f", "alt": "" }] }"#
        guard case .gallery(let embed) = try decode(PostEmbed.self, json) else {
            Issue.record("gallery として読み込まれていない")
            return
        }
        #expect(embed.items.first?.thumb == "t")
    }

    @Test func 外部リンクを読み込む() throws {
        let json = #"{ "$type": "app.bsky.embed.external#view", "external": { "uri": "https://e.com", "title": "E" } }"#
        guard case .external(let embed) = try decode(PostEmbed.self, json) else {
            Issue.record("external として読み込まれていない")
            return
        }
        #expect(embed.external.uri == "https://e.com")
        #expect(embed.external.title == "E")
    }

    @Test func 動画はすべての項目が省略可能() throws {
        let json = #"{ "$type": "app.bsky.embed.video#view", "alt": "動画の説明" }"#
        guard case .video(let embed) = try decode(PostEmbed.self, json) else {
            Issue.record("video として読み込まれていない")
            return
        }
        #expect(embed.alt == "動画の説明")
    }

    @Test(arguments: [
        #"{ "$type": "app.bsky.embed.unknownThing#view" }"#,
        #"{ "images": [] }"#,
    ])
    func 未知のtypeやtypeなしはunknownにする(json: String) throws {
        guard case .unknown = try decode(PostEmbed.self, json) else {
            Issue.record("unknown になっていない")
            return
        }
    }
}
