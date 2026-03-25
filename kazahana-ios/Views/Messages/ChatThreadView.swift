// ChatThreadView.swift
// kazahana-ios
// DM メッセージスレッド画面

import SwiftUI

struct ChatThreadView: View {
    @Environment(AuthViewModel.self) private var authVM
    let convo: ConvoView
    let chatService: ChatService

    @State private var viewModel: ChatThreadViewModel?
    @State private var messageText = ""
    @State private var scrollProxy: ScrollViewProxy?
    @State private var selectedAuthorDID: IdentifiableString? = nil

    private var myDID: String { authVM.client.currentSession?.did ?? "" }
    private var otherMember: ChatMember? { convo.otherMember(myDID: myDID) }

    var body: some View {
        VStack(spacing: 0) {
            // メッセージリスト
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        if viewModel?.isLoading == true && viewModel?.messages.isEmpty == true {
                            ProgressView()
                                .padding()
                        }

                        // 「もっと読む」ボタン
                        if let vm = viewModel, vm.messages.count >= 50 {
                            Button {
                                Task { await vm.loadMore() }
                            } label: {
                                if vm.isLoading {
                                    ProgressView()
                                } else {
                                    Text(String(localized: "dm.loadMore"))
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                            }
                            .padding(.vertical, 8)
                        }

                        ForEach(Array((viewModel?.messages ?? []).enumerated()), id: \.offset) { _, msg in
                            MessageBubbleView(
                                message: msg,
                                myDID: myDID,
                                onDelete: { msgId in
                                    Task { await viewModel?.deleteMessage(messageId: msgId) }
                                },
                                onReaction: { msgId, emoji in
                                    Task { await viewModel?.toggleReaction(messageId: msgId, emoji: emoji, myDID: myDID) }
                                }
                            )
                            .id(messageID(msg))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onAppear {
                    scrollProxy = proxy
                }
                .onChange(of: viewModel?.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }

            Divider()

            // 送信ボックス
            inputBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    if let did = otherMember?.did {
                        selectedAuthorDID = IdentifiableString(did)
                    }
                } label: {
                    Text(otherMember?.displayNameOrHandle ?? "")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationDestination(item: $selectedAuthorDID) { item in
            ProfileScreenView(actor: item.value)
                .environment(authVM)
        }
        .task {
            let vm = ChatThreadViewModel(chatService: chatService, convoId: convo.id)
            viewModel = vm
            await vm.loadInitial()
            vm.startPolling()
        }
        .onDisappear {
            viewModel?.stopPolling()
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(String(localized: "dm.messageInputPlaceholder"), text: $messageText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .padding(.vertical, 8)

            Button {
                let text = messageText
                messageText = ""
                Task { await viewModel?.sendMessage(text: text) }
            } label: {
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.blue)
                    .font(.title3)
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel?.isSending == true)
            .padding(.bottom, 10)
        }
        .padding(.horizontal, 12)
        .background(.bar)
    }

    // MARK: - Helpers

    private func messageID(_ msg: ChatMessageViewOrDeleted) -> String {
        switch msg {
        case .message(let m): return m.id
        case .deleted(let d): return d.id
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let last = viewModel?.messages.last else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(messageID(last), anchor: .bottom)
        }
    }
}

// MARK: - MessageBubbleView

/// リアクション絵文字のプリセット（デスクトップ版と同じ6種）
private let reactionPresets = ["❤️", "👍", "😂", "😮", "😢", "🎉"]

struct MessageBubbleView: View {
    let message: ChatMessageViewOrDeleted
    let myDID: String
    let onDelete: (String) -> Void
    let onReaction: (String, String) -> Void  // (messageId, emoji)

    @State private var showEmojiPicker = false

    private var isMine: Bool {
        switch message {
        case .message(let m): return m.sender.did == myDID
        case .deleted(let d): return d.sender.did == myDID
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isMine { Spacer(minLength: 40) }
            bubbleContent
                .contextMenu {
                    if case .message(let m) = message {
                        // リアクション追加
                        Button {
                            showEmojiPicker = true
                        } label: {
                            Label(String(localized: "dm.addReaction"), systemImage: "face.smiling")
                        }
                        Divider()
                        if isMine {
                            Button(role: .destructive) {
                                onDelete(m.id)
                            } label: {
                                Label(String(localized: "dm.deleteMessage"), systemImage: "trash")
                            }
                        }
                    }
                }
                .popover(isPresented: $showEmojiPicker) {
                    if case .message(let m) = message {
                        EmojiPickerView(
                            messageId: m.id,
                            myDID: myDID,
                            reactions: m.reactions ?? [],
                            onSelect: { emoji in
                                showEmojiPicker = false
                                onReaction(m.id, emoji)
                            }
                        )
                        .presentationCompactAdaptation(.popover)
                    }
                }
            if !isMine { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        switch message {
        case .message(let m):
            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                Text(richText(for: m))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isMine ? Color.blue : Color(.systemGray5))
                    .foregroundStyle(isMine ? .white : .primary)
                    .tint(isMine ? .white : .accentColor)
                    .environment(\.openURL, OpenURLAction { url in
                        if url.scheme == "kazahana" {
                            NotificationCenter.default.post(
                                name: .kazahanaDeepLink,
                                object: nil,
                                userInfo: ["url": url]
                            )
                            return .handled
                        }
                        return .systemAction
                    })
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                // リアクション表示
                if let reactions = m.reactions, !reactions.isEmpty {
                    ReactionSummaryView(
                        reactions: reactions,
                        myDID: myDID,
                        isMine: isMine,
                        onTap: { emoji in onReaction(m.id, emoji) }
                    )
                }

                if let date = m.sentDate {
                    Text(date, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }

        case .deleted:
            Text(String(localized: "dm.deletedMessage"))
                .font(.subheadline)
                .italic()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    /// facets がある場合はリッチテキスト、なければ URL/ハッシュタグを自動検出してリッチテキスト化
    private func richText(for m: ChatMessageView) -> AttributedString {
        if let facets = m.facets, !facets.isEmpty {
            return RichTextParser.attributedString(text: m.text, facets: facets)
        }
        // サーバーが facets を返さない場合はクライアント側で自動検出
        let detected = RichTextParser.detectFacets(in: m.text)
        if detected.isEmpty { return AttributedString(m.text) }
        let builtFacets = RichTextParser.buildFacets(from: detected.filter {
            if case .mention = $0.kind { return false } // DID 未解決メンションは除外
            return true
        })
        return RichTextParser.attributedString(text: m.text, facets: builtFacets.isEmpty ? nil : builtFacets)
    }
}

// MARK: - ReactionSummaryView（リアクション一覧）

struct ReactionSummaryView: View {
    let reactions: [ChatReaction]
    let myDID: String
    let isMine: Bool
    let onTap: (String) -> Void

    /// 絵文字ごとに集計 → [(emoji, count, isMine)]
    private var grouped: [(emoji: String, count: Int, mine: Bool)] {
        var map: [String: (count: Int, mine: Bool)] = [:]
        for r in reactions {
            let existing = map[r.value]
            let isMyReaction = r.sender.did == myDID
            map[r.value] = (
                count: (existing?.count ?? 0) + 1,
                mine: (existing?.mine ?? false) || isMyReaction
            )
        }
        // 出現順を維持するため reactions の順序を使用
        var seen = Set<String>()
        var result: [(emoji: String, count: Int, mine: Bool)] = []
        for r in reactions {
            if seen.insert(r.value).inserted, let entry = map[r.value] {
                result.append((emoji: r.value, count: entry.count, mine: entry.mine))
            }
        }
        return result
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(grouped, id: \.emoji) { item in
                Button {
                    onTap(item.emoji)
                } label: {
                    HStack(spacing: 2) {
                        Text(item.emoji)
                            .font(.caption)
                        if item.count > 1 {
                            Text("\(item.count)")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(item.mine ? .white : .primary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(item.mine ? Color.blue.opacity(0.8) : Color(.systemGray5))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - EmojiPickerView（絵文字選択ポップオーバー）

struct EmojiPickerView: View {
    let messageId: String
    let myDID: String
    let reactions: [ChatReaction]
    let onSelect: (String) -> Void

    /// 自分が既に付けているリアクション
    private var myReactions: Set<String> {
        Set(reactions.filter { $0.sender.did == myDID }.map(\.value))
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(reactionPresets, id: \.self) { emoji in
                let isSelected = myReactions.contains(emoji)
                Button {
                    onSelect(emoji)
                } label: {
                    Text(emoji)
                        .font(.title2)
                        .padding(8)
                        .background(isSelected ? Color.blue.opacity(0.2) : Color.clear)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
