// ConversationListView.swift
// kazahana-ios
// DM 会話一覧画面

import SwiftUI

struct ConversationListView: View {
    @Environment(AuthViewModel.self) private var authVM
    var onUnreadCountChanged: ((Int) -> Void)? = nil
    @State private var viewModel: ConversationListViewModel?
    @State private var chatService: ChatService?
    @State private var selectedConvo: ConvoView?
    @State private var showNewConversation = false

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    listContent(vm: vm, myDID: authVM.client.currentSession?.did ?? "")
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(String(localized: "tab.messages"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewConversation = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .navigationDestination(item: $selectedConvo) { convo in
                if let svc = chatService {
                    ChatThreadView(convo: convo, chatService: svc)
                        .environment(authVM)
                }
            }
            .sheet(isPresented: $showNewConversation) {
                if let svc = chatService {
                    NewConversationView(chatService: svc) { convo in
                        showNewConversation = false
                        selectedConvo = convo
                    }
                    .environment(authVM)
                }
            }
        }
        .task {
            setupServices()
            await viewModel?.loadInitial()
            viewModel?.startPolling()
        }
        .onDisappear {
            viewModel?.stopPolling()
        }
        .onChange(of: viewModel?.unreadCount) { _, newCount in
            onUnreadCountChanged?(newCount ?? 0)
        }
    }

    // MARK: - List Content

    @ViewBuilder
    private func listContent(vm: ConversationListViewModel, myDID: String) -> some View {
        List {
            ForEach(vm.conversations) { convo in
                ConversationRowView(
                    convo: convo,
                    myDID: myDID
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedConvo = convo
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { await vm.leaveConvo(convo.id) }
                    } label: {
                        Label(String(localized: "dm.leave"), systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    if convo.muted == true {
                        Button {
                            Task { await vm.unmuteConvo(convo.id) }
                        } label: {
                            Label(String(localized: "dm.unmute"), systemImage: "bell")
                        }
                        .tint(.blue)
                    } else {
                        Button {
                            Task { await vm.muteConvo(convo.id) }
                        } label: {
                            Label(String(localized: "dm.mute"), systemImage: "bell.slash")
                        }
                        .tint(.orange)
                    }
                }
                .onAppear {
                    if convo.id == vm.conversations.last?.id {
                        Task { await vm.loadMore() }
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
            }

            if vm.isLoading && !vm.conversations.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await vm.refresh()
        }
        .overlay {
            if vm.conversations.isEmpty && !vm.isLoading {
                ContentUnavailableView(
                    String(localized: "dm.noConversations"),
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(String(localized: "dm.noConversationsDescription"))
                )
            }
        }
        .overlay {
            if vm.isLoading && vm.conversations.isEmpty {
                ProgressView()
            }
        }
    }

    // MARK: - Setup

    private func setupServices() {
        guard viewModel == nil else { return }
        let svc = ChatService(client: authVM.client)
        chatService = svc
        let vm = ConversationListViewModel(chatService: svc)
        viewModel = vm
    }
}

// MARK: - ConversationRowView

struct ConversationRowView: View {
    let convo: ConvoView
    let myDID: String

    private var member: ChatMember? { convo.otherMember(myDID: myDID) }

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: member?.avatar, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(member?.displayNameOrHandle ?? "")
                        .font(.callout)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    if convo.muted == true {
                        Image(systemName: "bell.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let sentAt = convo.lastMessage?.sentAt {
                        Text(relativeTimeString(from: sentAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    if let preview = convo.lastMessage?.previewText {
                        Text(preview)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if convo.lastMessage != nil {
                        Text(String(localized: "dm.deletedMessage"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .italic()
                    }

                    Spacer()

                    if convo.unreadCount > 0 {
                        Text("\(min(convo.unreadCount, 99))")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue, in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }

    private func relativeTimeString(from isoString: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: isoString) else { return "" }
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return String(localized: "time.justNow") }
        if diff < 3600 {
            let mins = Int(diff / 60)
            return String.localizedStringWithFormat(String(localized: "time.minutesAgo %lld"), mins)
        }
        if diff < 86400 {
            let hours = Int(diff / 3600)
            return String.localizedStringWithFormat(String(localized: "time.hoursAgo %lld"), hours)
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
