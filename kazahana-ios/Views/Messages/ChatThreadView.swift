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
        .navigationTitle(otherMember?.displayNameOrHandle ?? "")
        .navigationBarTitleDisplayMode(.inline)
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

struct MessageBubbleView: View {
    let message: ChatMessageViewOrDeleted
    let myDID: String
    let onDelete: (String) -> Void

    private var isMine: Bool {
        switch message {
        case .message(let m): return m.sender.did == myDID
        case .deleted(let d): return d.sender.did == myDID
        }
    }

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 60) }
            bubbleContent
                .contextMenu {
                    if case .message(let m) = message, isMine {
                        Button(role: .destructive) {
                            onDelete(m.id)
                        } label: {
                            Label(String(localized: "dm.deleteMessage"), systemImage: "trash")
                        }
                    }
                }
            if !isMine { Spacer(minLength: 60) }
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        switch message {
        case .message(let m):
            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                Text(m.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isMine ? Color.blue : Color(.systemGray5))
                    .foregroundStyle(isMine ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

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
}
