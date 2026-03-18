// RichTextParser.swift
// kazahana-ios
// Bluesky Facet の解析（表示用 AttributedString 変換）と
// 投稿テキストからの Facet 自動生成

import Foundation
import SwiftUI

final class RichTextParser {

    // MARK: - 表示用: Facet → AttributedString

    /// 投稿テキストと Facet 配列から AttributedString を生成する
    /// Facet の index は UTF-8 バイトオフセットのため変換が必要
    static func attributedString(text: String, facets: [Facet]?) -> AttributedString {
        var result = AttributedString(text)

        guard let facets, !facets.isEmpty else { return result }

        let utf8 = Array(text.utf8)

        for facet in facets {
            let byteStart = facet.index.byteStart
            let byteEnd = facet.index.byteEnd

            // UTF-8 バイト範囲 → String.Index に変換
            guard byteStart < byteEnd,
                  byteEnd <= utf8.count,
                  let startIndex = byteOffsetToStringIndex(utf8Bytes: utf8, text: text, byteOffset: byteStart),
                  let endIndex = byteOffsetToStringIndex(utf8Bytes: utf8, text: text, byteOffset: byteEnd) else {
                continue
            }

            // AttributedString の Range に変換
            let atStart = AttributedString.Index(startIndex, within: result)
            let atEnd   = AttributedString.Index(endIndex, within: result)
            guard let atStart, let atEnd, atStart < atEnd else { continue }
            let range = atStart..<atEnd

            // Feature の種類に応じてスタイルを適用
            for feature in facet.features {
                switch feature.type {
                case "app.bsky.richtext.facet#mention":
                    result[range].foregroundColor = .accentColor
                    if let did = feature.did {
                        result[range].link = URL(string: "kazahana://profile/\(did)")
                    }
                case "app.bsky.richtext.facet#link":
                    result[range].foregroundColor = .accentColor
                    if let uri = feature.uri, let url = URL(string: uri) {
                        result[range].link = url
                    }
                case "app.bsky.richtext.facet#tag":
                    result[range].foregroundColor = .accentColor
                    if let tag = feature.tag {
                        result[range].link = URL(string: "kazahana://hashtag/\(tag)")
                    }
                default:
                    break
                }
            }
        }

        return result
    }

    // MARK: - 投稿用: テキスト → Facet 自動生成

    /// テキストから mention / URL / hashtag を検出して Facet 配列を生成する
    /// NOTE: mention の DID 解決は別途 resolveHandle API が必要なため、
    ///       ここでは byteOffset 計算のみ行い DID は呼び出し側で補完する
    static func detectFacets(in text: String) -> [DetectedFacet] {
        var detected: [DetectedFacet] = []
        let utf8Data = text.utf8

        // URL 検出
        let urlPattern = try! NSRegularExpression(
            pattern: #"https?://[^\s\u3000\u3001\u3002\uff0c\uff0e\u300c\u300d\uff08\uff09]+"#
        )
        let nsText = text as NSString
        for match in urlPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let urlString = String(text[range])
            let (byteStart, byteEnd) = byteRange(of: range, in: text)
            detected.append(DetectedFacet(
                byteStart: byteStart,
                byteEnd: byteEnd,
                kind: .link(uri: urlString)
            ))
        }
        _ = nsText // suppress warning

        // メンション検出 (@handle.bsky.social)
        let mentionPattern = try! NSRegularExpression(
            pattern: #"@([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}"#
        )
        for match in mentionPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let handle = String(text[range].dropFirst()) // @ を除く
            let (byteStart, byteEnd) = byteRange(of: range, in: text)
            detected.append(DetectedFacet(
                byteStart: byteStart,
                byteEnd: byteEnd,
                kind: .mention(handle: handle)
            ))
        }

        // ハッシュタグ検出 (#tag)
        let tagPattern = try! NSRegularExpression(
            pattern: #"(?<!\w)#(\w+)"#
        )
        for match in tagPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text),
                  let tagRange = Range(match.range(at: 1), in: text) else { continue }
            let tag = String(text[tagRange])
            let (byteStart, byteEnd) = byteRange(of: range, in: text)
            detected.append(DetectedFacet(
                byteStart: byteStart,
                byteEnd: byteEnd,
                kind: .tag(tag: tag)
            ))
        }

        return detected.sorted { $0.byteStart < $1.byteStart }
    }

    /// DetectedFacet（DID解決済み）を Facet 配列に変換する
    static func buildFacets(from detected: [DetectedFacet]) -> [Facet] {
        detected.compactMap { d in
            let index = ByteSlice(byteStart: d.byteStart, byteEnd: d.byteEnd)
            switch d.kind {
            case .link(let uri):
                return Facet(index: index, features: [
                    FacetFeature(type: "app.bsky.richtext.facet#link", did: nil, uri: uri, tag: nil)
                ])
            case .mention(_, let did):
                guard let did else { return nil } // DID 未解決は除外
                return Facet(index: index, features: [
                    FacetFeature(type: "app.bsky.richtext.facet#mention", did: did, uri: nil, tag: nil)
                ])
            case .tag(let tag):
                return Facet(index: index, features: [
                    FacetFeature(type: "app.bsky.richtext.facet#tag", did: nil, uri: nil, tag: tag)
                ])
            }
        }
    }

    // MARK: - Private helpers

    /// UTF-8 バイトオフセット → String.Index
    private static func byteOffsetToStringIndex(utf8Bytes: [UInt8], text: String, byteOffset: Int) -> String.Index? {
        guard byteOffset >= 0, byteOffset <= utf8Bytes.count else { return nil }
        // UTF-8 の先頭 byteOffset バイト分の部分文字列を作り、そこから Index を取得
        let prefix = utf8Bytes.prefix(byteOffset)
        return String(bytes: prefix, encoding: .utf8).flatMap { s in
            text.index(text.startIndex, offsetBy: s.count, limitedBy: text.endIndex)
        }
    }

    /// String.Range → UTF-8 バイト範囲
    private static func byteRange(of range: Range<String.Index>, in text: String) -> (Int, Int) {
        let prefix = text[..<range.lowerBound]
        let slice  = text[range]
        let start  = prefix.utf8.count
        let end    = start + slice.utf8.count
        return (start, end)
    }
}

// MARK: - 検出結果モデル

struct DetectedFacet {
    let byteStart: Int
    let byteEnd: Int
    var kind: Kind

    enum Kind {
        case mention(handle: String, did: String? = nil)
        case link(uri: String)
        case tag(tag: String)
    }
}
