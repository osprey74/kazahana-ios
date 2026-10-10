//
//  RichTextParserTests.swift
//  kazahana-iosTests
//

import Foundation
import Testing
@testable import kazahana

@MainActor
struct RichTextParserDetectFacetsTests {

    @Test func URLのバイトオフセットは日本語を3バイトで数える() throws {
        let facets = RichTextParser.detectFacets(in: "こんにちは https://example.com")
        let facet = try #require(facets.first)
        #expect(facets.count == 1)
        #expect(facet.byteStart == 16)  // "こんにちは" 15 バイト + 空白 1 バイト
        #expect(facet.byteEnd == 35)    // URL 19 バイト
        guard case .link(let uri) = facet.kind else {
            Issue.record("link として検出されていない")
            return
        }
        #expect(uri == "https://example.com")
    }

    @Test func URLは全角句読点の手前で終わる() throws {
        let facets = RichTextParser.detectFacets(in: "見て https://example.com/a。次へ")
        let facet = try #require(facets.first)
        guard case .link(let uri) = facet.kind else {
            Issue.record("link として検出されていない")
            return
        }
        #expect(uri == "https://example.com/a")
    }

    @Test func メンションはハンドルから先頭の＠を除く() throws {
        let facets = RichTextParser.detectFacets(in: "hi @alice.bsky.social!")
        let facet = try #require(facets.first)
        #expect(facet.byteStart == 3)
        #expect(facet.byteEnd == 21)
        guard case .mention(let handle, let did) = facet.kind else {
            Issue.record("mention として検出されていない")
            return
        }
        #expect(handle == "alice.bsky.social")
        #expect(did == nil)
    }

    @Test func ハッシュタグは日本語を含み範囲に＃を含む() throws {
        let facets = RichTextParser.detectFacets(in: "#日本語 です")
        let facet = try #require(facets.first)
        #expect(facet.byteStart == 0)
        #expect(facet.byteEnd == 10)  // "#" 1 バイト + 3 文字 × 3 バイト
        guard case .tag(let tag) = facet.kind else {
            Issue.record("tag として検出されていない")
            return
        }
        #expect(tag == "日本語")
    }

    @Test func 絵文字は4バイトで数える() throws {
        let facets = RichTextParser.detectFacets(in: "😀 #tag")
        let facet = try #require(facets.first)
        #expect(facet.byteStart == 5)
        #expect(facet.byteEnd == 9)
    }

    @Test func 単語の途中の＃はハッシュタグにしない() {
        #expect(RichTextParser.detectFacets(in: "abc#tag").isEmpty)
    }

    @Test func 全角の＃はハッシュタグにしない() {
        #expect(RichTextParser.detectFacets(in: "＃タグ").isEmpty)
    }

    @Test func 結果はバイト位置の昇順に並ぶ() {
        let facets = RichTextParser.detectFacets(in: "#a @bob.example.com https://x.com")
        #expect(facets.count == 3)
        #expect(facets.map(\.byteStart) == facets.map(\.byteStart).sorted())
    }
}

@MainActor
struct RichTextParserBuildFacetsTests {

    @Test func DID未解決のメンションは除外する() {
        let detected = [DetectedFacet(byteStart: 0, byteEnd: 6, kind: .mention(handle: "a.bsky.social"))]
        #expect(RichTextParser.buildFacets(from: detected).isEmpty)
    }

    @Test func 解決済みDIDを優先して使う() throws {
        let detected = [DetectedFacet(byteStart: 0, byteEnd: 6, kind: .mention(handle: "a.bsky.social", did: "did:plc:old"))]
        let facets = RichTextParser.buildFacets(from: detected, resolvedMentions: ["a.bsky.social": "did:plc:new"])
        let feature = try #require(facets.first?.features.first)
        #expect(feature.type == "app.bsky.richtext.facet#mention")
        #expect(feature.did == "did:plc:new")
    }

    @Test func リンクとタグのtypeとバイト範囲を引き継ぐ() {
        let detected = [
            DetectedFacet(byteStart: 0, byteEnd: 19, kind: .link(uri: "https://example.com")),
            DetectedFacet(byteStart: 20, byteEnd: 24, kind: .tag(tag: "tag")),
        ]
        let facets = RichTextParser.buildFacets(from: detected)
        #expect(facets.count == 2)
        #expect(facets[0].features.first?.type == "app.bsky.richtext.facet#link")
        #expect(facets[0].features.first?.uri == "https://example.com")
        #expect(facets[0].index.byteEnd == 19)
        #expect(facets[1].features.first?.type == "app.bsky.richtext.facet#tag")
        #expect(facets[1].features.first?.tag == "tag")
        #expect(facets[1].index.byteStart == 20)
    }
}

@MainActor
struct RichTextParserAttributedStringTests {

    private func links(in attributed: AttributedString) -> [URL] {
        attributed.runs.compactMap(\.link)
    }

    @Test func リンクのFacetにURLを付与する() {
        let facet = Facet(
            index: ByteSlice(byteStart: 6, byteEnd: 13),
            features: [FacetFeature(type: "app.bsky.richtext.facet#link", did: nil, uri: "https://example.com", tag: nil)]
        )
        let result = RichTextParser.attributedString(text: "Visit example", facets: [facet])
        #expect(links(in: result) == [URL(string: "https://example.com")!])
    }

    @Test func メンションとタグはアプリ内URLにする() {
        let text = "@a #t"
        let facets = [
            Facet(index: ByteSlice(byteStart: 0, byteEnd: 2),
                  features: [FacetFeature(type: "app.bsky.richtext.facet#mention", did: "did:plc:a", uri: nil, tag: nil)]),
            Facet(index: ByteSlice(byteStart: 3, byteEnd: 5),
                  features: [FacetFeature(type: "app.bsky.richtext.facet#tag", did: nil, uri: nil, tag: "t")]),
        ]
        let result = RichTextParser.attributedString(text: text, facets: facets)
        #expect(links(in: result) == [
            URL(string: "kazahana://profile/did:plc:a")!,
            URL(string: "kazahana://hashtag/t")!,
        ])
    }

    @Test func 範囲外や逆転したFacetは無視する() {
        let facets = [
            Facet(index: ByteSlice(byteStart: 0, byteEnd: 100),
                  features: [FacetFeature(type: "app.bsky.richtext.facet#link", did: nil, uri: "https://a.com", tag: nil)]),
            Facet(index: ByteSlice(byteStart: 3, byteEnd: 1),
                  features: [FacetFeature(type: "app.bsky.richtext.facet#link", did: nil, uri: "https://b.com", tag: nil)]),
        ]
        let result = RichTextParser.attributedString(text: "short", facets: facets)
        #expect(links(in: result).isEmpty)
        #expect(String(result.characters) == "short")
    }
}
