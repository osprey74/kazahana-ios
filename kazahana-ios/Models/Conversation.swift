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
    let kind: ConvoKind?

    /// 自分以外のメンバーを返す（1対1チャットで相手を取得）
    func otherMember(myDID: String) -> ChatMember? {
        members.first { $0.did != myDID }
    }

    /// 自分以外の全メンバーを返す（グループチャット用）
    func otherMembers(myDID: String) -> [ChatMember] {
        members.filter { $0.did != myDID }
    }

    /// グループ会話かどうか
    var isGroup: Bool {
        if case .group = kind { return true }
        return false
    }

    /// グループ会話の場合、GroupConvo を返す
    var groupConvo: GroupConvo? {
        if case .group(let g) = kind { return g }
        return nil
    }

    /// 表示名（グループ名 or 相手のハンドル）
    func displayName(myDID: String) -> String {
        if let group = groupConvo { return group.name }
        return otherMember(myDID: myDID)?.displayNameOrHandle ?? ""
    }

    /// ロック状態かどうか
    var isLocked: Bool {
        guard let g = groupConvo else { return false }
        return g.lockStatus == "locked" || g.lockStatus == "locked-permanently"
    }
}

extension ConvoView: Hashable {
    static func == (lhs: ConvoView, rhs: ConvoView) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - ConvoKind（1:1 / グループ判別）

enum ConvoKind: Codable {
    case direct
    case group(GroupConvo)

    private enum TypeKey: String, CodingKey { case type = "$type" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type)
        if type_.hasSuffix("#groupConvo") {
            self = .group(try GroupConvo(from: decoder))
        } else {
            self = .direct
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .direct:
            var container = encoder.container(keyedBy: TypeKey.self)
            try container.encode("chat.bsky.convo.defs#directConvo", forKey: .type)
        case .group(let g):
            try g.encode(to: encoder)
        }
    }
}

// MARK: - GroupConvo

struct GroupConvo: Codable {
    let createdAt: String?
    let name: String
    let memberCount: Int
    let memberLimit: Int?
    let lockStatus: String          // "unlocked" | "locked" | "locked-permanently"
    let lockStatusModerationOverride: Bool?
    let joinLink: JoinLinkView?
    let joinRequestCount: Int?          // owner のみ
    let unreadJoinRequestCount: Int?    // owner のみ

    private enum CodingKeys: String, CodingKey {
        case createdAt, name, memberCount, memberLimit, lockStatus
        case lockStatusModerationOverride, joinLink, joinRequestCount, unreadJoinRequestCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        memberCount = (try? container.decode(Int.self, forKey: .memberCount)) ?? 0
        memberLimit = try container.decodeIfPresent(Int.self, forKey: .memberLimit)
        lockStatus = (try? container.decode(String.self, forKey: .lockStatus)) ?? "unlocked"
        lockStatusModerationOverride = try container.decodeIfPresent(Bool.self, forKey: .lockStatusModerationOverride)
        // joinLink のデコード失敗を許容
        joinLink = try? container.decodeIfPresent(JoinLinkView.self, forKey: .joinLink)
        joinRequestCount = try container.decodeIfPresent(Int.self, forKey: .joinRequestCount)
        unreadJoinRequestCount = try container.decodeIfPresent(Int.self, forKey: .unreadJoinRequestCount)
    }
}

// MARK: - JoinLinkView

struct JoinLinkView: Codable {
    let code: String?
    let disabled: Bool?
    let enabledStatus: String?  // "enabled" | "disabled"
    let requireApproval: Bool?
    let joinRule: String?       // "anyone" | "followedByOwner"

    var isEnabled: Bool {
        if let status = enabledStatus { return status == "enabled" }
        return disabled != true
    }

    private enum CodingKeys: String, CodingKey {
        case code, disabled, enabledStatus, requireApproval, joinRule
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(String.self, forKey: .code)
        disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled)
        enabledStatus = try container.decodeIfPresent(String.self, forKey: .enabledStatus)
        requireApproval = try container.decodeIfPresent(Bool.self, forKey: .requireApproval)
        joinRule = try container.decodeIfPresent(String.self, forKey: .joinRule)
    }
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
    let embed: ChatMessageEmbed?

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

// MARK: - ChatMessageEmbed（メッセージ内埋め込み）

enum ChatMessageEmbed: Codable {
    case joinLink(JoinLinkEmbedData)
    case unknown

    private enum TypeKey: String, CodingKey { case type = "$type" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        if type_.contains("joinLink") {
            self = .joinLink(try JoinLinkEmbedData(from: decoder))
        } else {
            self = .unknown
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .joinLink(let v): try v.encode(to: encoder)
        case .unknown: break
        }
    }
}

// MARK: - JoinLinkEmbedData

struct JoinLinkEmbedData: Codable {
    let joinLinkPreview: JoinLinkPreview?

    enum JoinLinkPreview: Codable {
        case active(JoinLinkPreviewActive)
        case disabled
        case invalid

        private enum TypeKey: String, CodingKey { case type = "$type" }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: TypeKey.self)
            let type_ = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
            if type_.contains("disabledJoinLinkPreview") {
                self = .disabled
            } else if type_.contains("invalidJoinLinkPreview") {
                self = .invalid
            } else {
                self = .active(try JoinLinkPreviewActive(from: decoder))
            }
        }

        func encode(to encoder: Encoder) throws {
            if case .active(let a) = self { try a.encode(to: encoder) }
        }
    }
}

struct JoinLinkPreviewActive: Codable {
    let code: String?
    let name: String?
    let memberCount: Int?
    let owner: ChatMember?
}

// MARK: - SystemMessageView

struct SystemMessageView: Codable, Identifiable {
    let id: String
    let rev: String
    let sentAt: String
    let data: SystemMessageData

    var sentDate: Date? {
        ISO8601DateFormatter().date(from: sentAt)
    }
}

// MARK: - SystemMessageData（14 種のシステムメッセージ）

enum SystemMessageData: Codable {
    case addMember(actor: ChatMember?, subject: ChatMember?)
    case removeMember(actor: ChatMember?, subject: ChatMember?)
    case memberJoin(actor: ChatMember?)
    case memberLeave(actor: ChatMember?)
    case lockConvo(actor: ChatMember?)
    case unlockConvo(actor: ChatMember?)
    case lockConvoPermanently
    case editGroup(actor: ChatMember?)
    case createJoinLink(actor: ChatMember?)
    case editJoinLink(actor: ChatMember?)
    case enableJoinLink(actor: ChatMember?)
    case disableJoinLink(actor: ChatMember?)
    case unknown

    private enum TypeKey: String, CodingKey { case type = "$type" }
    private enum DataKeys: String, CodingKey {
        case actor, subject, member, addedBy, removedBy, lockedBy, unlockedBy
    }

    init(from decoder: Decoder) throws {
        let typeContainer = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try typeContainer.decodeIfPresent(String.self, forKey: .type) ?? ""
        let container = try decoder.container(keyedBy: DataKeys.self)

        if type_.hasSuffix("AddMember") || type_.hasSuffix("addMember") {
            let subject = try container.decodeIfPresent(ChatMember.self, forKey: .member)
                ?? container.decodeIfPresent(ChatMember.self, forKey: .subject)
            let actor = try container.decodeIfPresent(ChatMember.self, forKey: .addedBy)
                ?? container.decodeIfPresent(ChatMember.self, forKey: .actor)
            self = .addMember(actor: actor, subject: subject)
        } else if type_.hasSuffix("RemoveMember") || type_.hasSuffix("removeMember") {
            let subject = try container.decodeIfPresent(ChatMember.self, forKey: .member)
                ?? container.decodeIfPresent(ChatMember.self, forKey: .subject)
            let actor = try container.decodeIfPresent(ChatMember.self, forKey: .removedBy)
                ?? container.decodeIfPresent(ChatMember.self, forKey: .actor)
            self = .removeMember(actor: actor, subject: subject)
        } else if type_.hasSuffix("MemberJoin") || type_.hasSuffix("memberJoin") {
            let actor = try container.decodeIfPresent(ChatMember.self, forKey: .member)
                ?? container.decodeIfPresent(ChatMember.self, forKey: .actor)
            self = .memberJoin(actor: actor)
        } else if type_.hasSuffix("MemberLeave") || type_.hasSuffix("memberLeave") {
            let actor = try container.decodeIfPresent(ChatMember.self, forKey: .member)
                ?? container.decodeIfPresent(ChatMember.self, forKey: .actor)
            self = .memberLeave(actor: actor)
        } else if type_.hasSuffix("LockConvoPermanently") || type_.hasSuffix("lockConvoPermanently") {
            self = .lockConvoPermanently
        } else if type_.hasSuffix("LockConvo") || type_.hasSuffix("lockConvo") {
            let actor = try container.decodeIfPresent(ChatMember.self, forKey: .lockedBy)
                ?? container.decodeIfPresent(ChatMember.self, forKey: .actor)
            self = .lockConvo(actor: actor)
        } else if type_.hasSuffix("UnlockConvo") || type_.hasSuffix("unlockConvo") {
            let actor = try container.decodeIfPresent(ChatMember.self, forKey: .unlockedBy)
                ?? container.decodeIfPresent(ChatMember.self, forKey: .actor)
            self = .unlockConvo(actor: actor)
        } else if type_.hasSuffix("EditGroup") || type_.hasSuffix("editGroup") {
            let actor = try container.decodeIfPresent(ChatMember.self, forKey: .actor)
            self = .editGroup(actor: actor)
        } else if type_.hasSuffix("CreateJoinLink") || type_.hasSuffix("createJoinLink") {
            let actor = try container.decodeIfPresent(ChatMember.self, forKey: .actor)
            self = .createJoinLink(actor: actor)
        } else if type_.hasSuffix("EditJoinLink") || type_.hasSuffix("editJoinLink") {
            let actor = try container.decodeIfPresent(ChatMember.self, forKey: .actor)
            self = .editJoinLink(actor: actor)
        } else if type_.hasSuffix("EnableJoinLink") || type_.hasSuffix("enableJoinLink") {
            let actor = try container.decodeIfPresent(ChatMember.self, forKey: .actor)
            self = .enableJoinLink(actor: actor)
        } else if type_.hasSuffix("DisableJoinLink") || type_.hasSuffix("disableJoinLink") {
            let actor = try container.decodeIfPresent(ChatMember.self, forKey: .actor)
            self = .disableJoinLink(actor: actor)
        } else {
            self = .unknown
        }
    }

    func encode(to encoder: Encoder) throws {
        // 受信専用のため encode は最低限
    }

    /// 表示用テキスト
    func displayText() -> String {
        switch self {
        case .addMember(_, let subject):
            let name = subject?.displayNameOrHandle ?? "?"
            return String(localized: "dm.system.addMember \(name)")
        case .removeMember(_, let subject):
            let name = subject?.displayNameOrHandle ?? "?"
            return String(localized: "dm.system.removeMember \(name)")
        case .memberJoin(let actor):
            let name = actor?.displayNameOrHandle ?? "?"
            return String(localized: "dm.system.memberJoin \(name)")
        case .memberLeave(let actor):
            let name = actor?.displayNameOrHandle ?? "?"
            return String(localized: "dm.system.memberLeave \(name)")
        case .lockConvo:
            return String(localized: "dm.system.lockConvo")
        case .unlockConvo:
            return String(localized: "dm.system.unlockConvo")
        case .lockConvoPermanently:
            return String(localized: "dm.system.lockConvoPermanently")
        case .editGroup:
            return String(localized: "dm.system.editGroup")
        case .createJoinLink:
            return String(localized: "dm.system.createJoinLink")
        case .editJoinLink:
            return String(localized: "dm.system.editJoinLink")
        case .enableJoinLink:
            return String(localized: "dm.system.enableJoinLink")
        case .disableJoinLink:
            return String(localized: "dm.system.disableJoinLink")
        case .unknown:
            return ""
        }
    }
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
    case system(SystemMessageView)

    private enum TypeKey: String, CodingKey { case type = "$type" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type)
        if type_.hasSuffix("deletedMessageView") {
            self = .deleted(try DeletedMessageView(from: decoder))
        } else if type_.hasSuffix("systemMessageView") {
            self = .system(try SystemMessageView(from: decoder))
        } else {
            self = .message(try ChatMessageView(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .message(let m): try m.encode(to: encoder)
        case .deleted(let d): try d.encode(to: encoder)
        case .system(let s): try s.encode(to: encoder)
        }
    }

    /// テキストプレビュー（会話一覧で使用）
    var previewText: String? {
        switch self {
        case .message(let m): return m.text
        case .deleted: return nil
        case .system(let s): return s.data.displayText()
        }
    }

    var sentAt: String {
        switch self {
        case .message(let m): return m.sentAt
        case .deleted(let d): return d.sentAt
        case .system(let s): return s.sentAt
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

struct ListConvoRequestsResponse: Decodable {
    let convos: [ConvoView]
    let cursor: String?
}

struct GetJoinLinkPreviewsResponse: Decodable {
    let joinLinkPreviews: [JoinLinkPreviewItem]
}

/// getJoinLinkPreviews が返す各プレビュー（$type で active/disabled/invalid を判別）
enum JoinLinkPreviewItem: Codable {
    case active(JoinLinkPreviewActive)
    case disabled
    case invalid

    private enum TypeKey: String, CodingKey { case type = "$type" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        if type_.contains("disabledJoinLinkPreview") {
            self = .disabled
        } else if type_.contains("invalidJoinLinkPreview") {
            self = .invalid
        } else {
            self = .active(try JoinLinkPreviewActive(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        if case .active(let a) = self { try a.encode(to: encoder) }
    }
}

struct RequestJoinResponse: Decodable {
    let status: String      // "joined" | "pending"
    let convo: ConvoView?
}

struct WithdrawJoinRequestResponse: Decodable {
    let convoId: String?
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

struct RequestJoinBody: Encodable {
    let code: String
}

struct WithdrawJoinRequestBody: Encodable {
    let convoId: String
}

struct LockConvoBody: Encodable {
    let convoId: String
}

struct UnlockConvoBody: Encodable {
    let convoId: String
}

// MARK: - グループ管理 body 型（Phase 3）

struct CreateGroupBody: Encodable {
    let name: String
    let members: [String]   // DID の配列（≤49）
}

struct EditGroupBody: Encodable {
    let convoId: String
    let name: String
}

struct AddMembersBody: Encodable {
    let convoId: String
    let members: [String]
}

struct RemoveMembersBody: Encodable {
    let convoId: String
    let members: [String]
}

struct CreateJoinLinkBody: Encodable {
    let convoId: String
    let joinRule: String        // "anyone" etc.
    let requireApproval: Bool?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(convoId, forKey: .convoId)
        try container.encode(joinRule, forKey: .joinRule)
        try container.encodeIfPresent(requireApproval, forKey: .requireApproval)
    }
    private enum CodingKeys: String, CodingKey { case convoId, joinRule, requireApproval }
}

struct EditJoinLinkBody: Encodable {
    let convoId: String
    let joinRule: String?
    let requireApproval: Bool?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(convoId, forKey: .convoId)
        try container.encodeIfPresent(joinRule, forKey: .joinRule)
        try container.encodeIfPresent(requireApproval, forKey: .requireApproval)
    }
    private enum CodingKeys: String, CodingKey { case convoId, joinRule, requireApproval }
}

struct EnableJoinLinkBody: Encodable {
    let convoId: String
}

struct DisableJoinLinkBody: Encodable {
    let convoId: String
}

struct ApproveJoinRequestBody: Encodable {
    let convoId: String
    let did: String
}

struct RejectJoinRequestBody: Encodable {
    let convoId: String
    let did: String
}

struct UpdateJoinRequestsReadBody: Encodable {
    let convoId: String
}

// MARK: - グループ管理レスポンス型（Phase 3）

struct CreateGroupResponse: Decodable {
    let convo: ConvoView
}

struct EditGroupResponse: Decodable {
    let convo: ConvoView
}

struct AddMembersResponse: Decodable {
    let convo: ConvoView
}

struct RemoveMembersResponse: Decodable {
    let convo: ConvoView
}

/// グループ操作の汎用レスポンス（convo が含まれない場合もある）
struct GroupOperationResponse: Decodable {
    let convo: ConvoView?
}

struct JoinRequestView: Decodable, Identifiable {
    let did: String
    let handle: String
    let displayName: String?
    let avatar: String?
    let requestedAt: String?

    var id: String { did }
    var displayNameOrHandle: String {
        let name = displayName ?? ""
        return name.isEmpty ? handle : name
    }
}

struct ListJoinRequestsResponse: Decodable {
    let requests: [JoinRequestView]
    let cursor: String?
}

struct ApproveJoinRequestResponse: Decodable {
    let convo: ConvoView?
}

struct RejectJoinRequestResponse: Decodable {
    let convo: ConvoView?
}

// MARK: - チャットプライバシー設定（Phase 4）

struct ChatDeclaration: Codable {
    var allowIncoming: String
    var allowGroupInvites: String

    enum CodingKeys: String, CodingKey {
        case allowIncoming, allowGroupInvites
    }

    init(allowIncoming: String = "all", allowGroupInvites: String = "all") {
        self.allowIncoming = allowIncoming
        self.allowGroupInvites = allowGroupInvites
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        allowIncoming = try container.decodeIfPresent(String.self, forKey: .allowIncoming) ?? "all"
        allowGroupInvites = try container.decodeIfPresent(String.self, forKey: .allowGroupInvites) ?? "all"
    }
}

struct ListMutualGroupsResponse: Decodable {
    let groups: [ConvoView]?
}

enum ChatServiceError: Error {
    case notLoggedIn
}

// MARK: - putRecord ヘルパー型

struct PutRecordBody {
    let repo: String
    let collection: String
    let rkey: String
    let record: any Encodable
}

struct PutRecordResponse: Decodable {
    let uri: String?
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

struct LockConvoResponse: Decodable {
    let convo: ConvoView
}

struct UnlockConvoResponse: Decodable {
    let convo: ConvoView
}
