//
//  TestSupport.swift
//  kazahana-iosTests
//
//  テスト共通ヘルパー
//

import Foundation

/// JSON 文字列を指定型にデコードする
func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

/// 最小構成の PostView JSON を生成する
func postViewJSON(
    uri: String = "at://did:plc:author/app.bsky.feed.post/1",
    text: String = "hello",
    embed: String? = nil,
    labels: String? = nil,
    authorLabels: String? = nil
) -> String {
    """
    {
      "uri": "\(uri)",
      "cid": "bafy",
      "author": {
        "did": "did:plc:author",
        "handle": "author.bsky.social"
        \(authorLabels.map { ", \"labels\": \($0)" } ?? "")
      },
      "record": { "text": "\(text)" },
      "indexedAt": "2026-10-10T00:00:00.000Z"
      \(embed.map { ", \"embed\": \($0)" } ?? "")
      \(labels.map { ", \"labels\": \($0)" } ?? "")
    }
    """
}
