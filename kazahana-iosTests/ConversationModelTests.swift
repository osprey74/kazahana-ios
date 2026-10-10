//
//  ConversationModelTests.swift
//  kazahana-iosTests
//

import Foundation
import Testing
@testable import kazahana

@MainActor
struct ChatMemberNameTests {

    private let members = [
        ChatMember(did: "did:plc:alice", handle: "alice.bsky.social", displayName: "Alice", avatar: nil),
        ChatMember(did: "did:plc:bob", handle: "bob.bsky.social", displayName: "", avatar: nil),
    ]

    @Test(arguments: [
        ("did:plc:abcdefghijkl", "abcd…ijkl"),
        ("did:plc:abcdefgh", "abcdefgh"),       // 8 文字以下はそのまま
        ("did:web:example.com", "exam….com"),
        ("not-a-did", "not-a-did"),             // did: で始まらなければそのまま
    ])
    func 短縮DIDの表示(did: String, expected: String) {
        #expect(ChatMember.shortDID(did) == expected)
    }

    @Test func 名前は表示名を優先する() {
        #expect(members.resolveName(did: "did:plc:alice") == "Alice")
    }

    @Test func 表示名が空ならハンドルを使う() {
        #expect(members.resolveName(did: "did:plc:bob") == "bob.bsky.social")
    }

    @Test func メンバーにいなければ短縮DIDを使う() {
        #expect(members.resolveName(did: "did:plc:unknownmember") == "unkn…mber")
    }
}

@MainActor
struct ChatMessageDecodingTests {

    @Test func 通常のメッセージを読み込む() throws {
        let json = #"{ "$type": "chat.bsky.convo.defs#messageView", "id": "m1", "rev": "1", "text": "hi", "sender": { "did": "did:plc:a" }, "sentAt": "2026-10-10T00:00:00Z" }"#
        guard case .message(let message) = try decode(ChatMessageViewOrDeleted.self, json) else {
            Issue.record("message として読み込まれていない")
            return
        }
        #expect(message.text == "hi")
        #expect(message.sender.did == "did:plc:a")
    }

    @Test func 削除済みメッセージを読み込む() throws {
        let json = #"{ "$type": "chat.bsky.convo.defs#deletedMessageView", "id": "m1", "rev": "1", "sender": { "did": "did:plc:a" }, "sentAt": "2026-10-10T00:00:00Z" }"#
        guard case .deleted = try decode(ChatMessageViewOrDeleted.self, json) else {
            Issue.record("deleted として読み込まれていない")
            return
        }
    }

    @Test func DIDだけの参照ユーザーでもシステムメッセージを読み込む() throws {
        let json = """
        {
          "$type": "chat.bsky.convo.defs#systemMessageView",
          "id": "s1", "rev": "1", "sentAt": "2026-10-10T00:00:00Z",
          "data": {
            "$type": "chat.bsky.convo.defs#systemMessageDataAddMember",
            "member": { "did": "did:plc:new" },
            "addedBy": { "did": "did:plc:owner" }
          }
        }
        """
        guard case .system(let system) = try decode(ChatMessageViewOrDeleted.self, json),
              case .addMember(let actor, let subject) = system.data else {
            Issue.record("addMember のシステムメッセージとして読み込まれていない")
            return
        }
        #expect(actor?.did == "did:plc:owner")
        #expect(subject?.did == "did:plc:new")
    }

    @Test func typeがなければ失敗する() {
        #expect(throws: (any Error).self) {
            try decode(ChatMessageViewOrDeleted.self, #"{ "id": "m1", "rev": "1", "sender": { "did": "d" }, "sentAt": "x" }"#)
        }
    }
}

@MainActor
struct SystemMessageDataTests {

    private func data(_ type: String, _ extra: String = "") throws -> SystemMessageData {
        try decode(SystemMessageData.self, #"{ "$type": "chat.bsky.convo.defs#\#(type)" \#(extra) }"#)
    }

    @Test func 退出を読み込む() throws {
        guard case .memberLeave(let actor) = try data("systemMessageDataMemberLeave", #", "member": { "did": "did:plc:a" }"#) else {
            Issue.record("memberLeave になっていない")
            return
        }
        #expect(actor?.did == "did:plc:a")
    }

    @Test func ロックを読み込む() throws {
        guard case .lockConvo(let actor) = try data("systemMessageDataLockConvo", #", "lockedBy": { "did": "did:plc:a" }"#) else {
            Issue.record("lockConvo になっていない")
            return
        }
        #expect(actor?.did == "did:plc:a")
    }

    @Test func 永久ロックはロックより先に判定する() throws {
        guard case .lockConvoPermanently = try data("systemMessageDataLockConvoPermanently") else {
            Issue.record("lockConvoPermanently になっていない")
            return
        }
    }

    @Test func ロック解除をロックと区別して読み込む() throws {
        // "UnlockConvo" も "lockConvo" で終わるため、以前はロックとして読み込まれていた
        let result = try data("systemMessageDataUnlockConvo", #", "unlockedBy": { "did": "did:plc:a" }"#)
        guard case .unlockConvo(let actor) = result else {
            Issue.record("unlockConvo になっていない: \(result)")
            return
        }
        #expect(actor?.did == "did:plc:a")
    }

    @Test func ロック解除の表示文言はロックと異なる() throws {
        let unlock = try data("systemMessageDataUnlockConvo").displayText(members: [])
        let lock = try data("systemMessageDataLockConvo").displayText(members: [])
        #expect(!unlock.isEmpty)
        #expect(unlock != lock)
    }

    @Test func 未知のtypeはunknownにする() throws {
        guard case .unknown = try data("systemMessageDataSomethingNew") else {
            Issue.record("unknown になっていない")
            return
        }
    }
}
