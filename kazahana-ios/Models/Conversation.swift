// Conversation.swift
// kazahana-ios
// chat.bsky.convo.* API のモデル型

import Foundation

// MARK: - ConvoView（会話）

struct ConvoView: Codable, Identifiable {
    let id: String
    let rev: String
    let members: [ChatMember]
    let lastMessage: ChatMessageViewOrDeleted?
    let unreadCount: Int
    let muted: Bool?
    let opened: Bool?
    let status: String?

    /// 自分以外のメンバーを返す（1対1チャットで相手を取得）
    func otherMember(myDID: String) -> ChatMember? {
        members.first { $0.did != myDID }
    }
}

extension ConvoView: Hashable {
    static func == (lhs: ConvoView, rhs: ConvoView) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - ChatMember

struct ChatMember: Codable, Identifiable {
    let did: String
    let handle: String
    let displayName: String?
    let avatar: String?

    var id: String { did }

    var displayNameOrHandle: String {
        let name = displayName ?? ""
        return name.isEmpty ? handle : name
    }
}

// MARK: - ChatMessageView

struct ChatMessageView: Codable, Identifiable {
    let id: String
    let rev: String
    let text: String
    let sender: ChatMessageSender
    let sentAt: String
    let facets: [Facet]?
    let reactions: [ChatReaction]?

    var sentDate: Date? {
        ISO8601DateFormatter().date(from: sentAt)
    }
}

struct ChatMessageSender: Codable {
    let did: String
}

// MARK: - ChatReaction

struct ChatReaction: Codable {
    let value: String
    let sender: ChatMessageSender
}

// MARK: - DeletedMessageView

struct DeletedMessageView: Codable {
    let id: String
    let rev: String
    let sender: ChatMessageSender
    let sentAt: String
}

// MARK: - ChatMessageViewOrDeleted（$type による判別）

enum ChatMessageViewOrDeleted: Codable {
    case message(ChatMessageView)
    case deleted(DeletedMessageView)

    private enum TypeKey: String, CodingKey { case type = "$type" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type)
        if type_.hasSuffix("deletedMessageView") {
            self = .deleted(try DeletedMessageView(from: decoder))
        } else {
            self = .message(try ChatMessageView(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .message(let m): try m.encode(to: encoder)
        case .deleted(let d): try d.encode(to: encoder)
        }
    }

    /// テキストプレビュー（会話一覧で使用）
    var previewText: String? {
        switch self {
        case .message(let m): return m.text
        case .deleted: return nil
        }
    }

    var sentAt: String {
        switch self {
        case .message(let m): return m.sentAt
        case .deleted(let d): return d.sentAt
        }
    }
}

// MARK: - API レスポンス型

struct ListConvosResponse: Decodable {
    let convos: [ConvoView]
    let cursor: String?
}

struct GetConvoResponse: Decodable {
    let convo: ConvoView
}

struct GetMessagesResponse: Decodable {
    let messages: [ChatMessageViewOrDeleted]
    let cursor: String?
}

struct SendMessageResponse: Decodable {
    let id: String
    let rev: String
    let text: String
    let sender: ChatMessageSender
    let sentAt: String
    let facets: [Facet]?
    let reactions: [ChatReaction]?
}

struct AddReactionResponse: Decodable {
    let id: String
    let rev: String
    let text: String
    let sender: ChatMessageSender
    let sentAt: String
    let facets: [Facet]?
    let reactions: [ChatReaction]?
}

struct RemoveReactionResponse: Decodable {
    let id: String
    let rev: String
    let text: String
    let sender: ChatMessageSender
    let sentAt: String
    let facets: [Facet]?
    let reactions: [ChatReaction]?
}

struct GetConvoForMembersResponse: Decodable {
    let convo: ConvoView
}

struct GetUnreadCountResponse: Decodable {
    let count: Int
}

// MARK: - API リクエスト body 型

struct SendMessageBody: Encodable {
    let convoId: String
    let message: MessageInput

    struct MessageInput: Encodable {
        let text: String
        let facets: [Facet]?
    }
}

struct DeleteMessageBody: Encodable {
    let convoId: String
    let messageId: String
}

struct UpdateReadBody: Encodable {
    let convoId: String
    let messageId: String?
}

struct MuteConvoBody: Encodable {
    let convoId: String
}

struct UnmuteConvoBody: Encodable {
    let convoId: String
}

struct LeaveConvoBody: Encodable {
    let convoId: String
}

struct AcceptConvoBody: Encodable {
    let convoId: String
}

struct AddReactionBody: Encodable {
    let convoId: String
    let messageId: String
    let value: String
}

struct RemoveReactionBody: Encodable {
    let convoId: String
    let messageId: String
    let value: String
}

// MARK: - 削除レスポンス

struct DeleteMessageForSelfResponse: Decodable {
    let id: String
    let rev: String
    let sender: ChatMessageSender
    let sentAt: String
}

struct MuteConvoResponse: Decodable {
    let convo: ConvoView
}

struct UnmuteConvoResponse: Decodable {
    let convo: ConvoView
}

struct LeaveConvoResponse: Decodable {
    let rev: String
}

struct AcceptConvoResponse: Decodable {
    let rev: String
}
