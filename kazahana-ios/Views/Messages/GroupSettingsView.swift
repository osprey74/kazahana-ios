// GroupSettingsView.swift
// kazahana-ios
// グループ設定画面（owner 操作 + 全員共通操作）

import SwiftUI

struct GroupSettingsView: View {
    @Environment(AuthViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss

    let chatService: ChatService
    @State var convo: ConvoView

    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var showLeaveConfirm = false
    @State private var showAddMembers = false
    @State private var kickTarget: ChatMember?
    @State private var joinRequests: [JoinRequestView] = []
    @State private var isLoadingRequests = false
    @State private var isJoinLinkOperating = false
    @State private var errorMessage: String?
    @State private var toastMessage: String?

    private var myDID: String { authVM.client.currentSession?.did ?? "" }
    private var group: GroupConvo? { convo.groupConvo }
    // owner = members 配列の最初のメンバー（Bluesky の慣例）
    private var isOwner: Bool { convo.members.first?.did == myDID }

    var body: some View {
        List {
            // グループ情報
            groupInfoSection

            // メンバー一覧
            membersSection

            // 招待リンク（owner のみ）
            if isOwner {
                joinLinkSection
            }

            // 参加申請（owner のみ）
            if isOwner, let count = group?.joinRequestCount, count > 0 {
                joinRequestsSection
            }

            // ロック（owner のみ）
            if isOwner {
                lockSection
            }

            // 操作
            actionsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(String(localized: "dm.groupSettings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(String(localized: "common.error"), isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "common.ok")) { errorMessage = nil }
        } message: {
            if let msg = errorMessage { Text(msg) }
        }
        .alert(String(localized: "dm.createGroup.namePlaceholder"), isPresented: $isEditingName) {
            TextField("", text: $editedName)
            Button(String(localized: "common.ok")) {
                Task { await updateGroupName() }
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
        .confirmationDialog(
            String(localized: "dm.groupSettings.leaveConfirm"),
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "dm.leave"), role: .destructive) {
                Task { await leaveGroup() }
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
        .confirmationDialog(
            String(localized: "dm.groupSettings.kickConfirm"),
            isPresented: .init(
                get: { kickTarget != nil },
                set: { if !$0 { kickTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "dm.groupSettings.kick"), role: .destructive) {
                if let target = kickTarget {
                    Task { await kickMember(target) }
                }
            }
            Button(String(localized: "common.cancel"), role: .cancel) { kickTarget = nil }
        }
        .sheet(isPresented: $showAddMembers) {
            AddMembersSheet(chatService: chatService, convoId: convo.id) { updatedConvo in
                convo = updatedConvo
                showAddMembers = false
            }
            .environment(authVM)
        }
        .overlay(alignment: .bottom) {
            if let msg = toastMessage {
                Text(msg)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toastMessage)
        .task {
            if isOwner {
                await loadJoinRequests()
            }
        }
    }

    // MARK: - Group Info

    @ViewBuilder
    private var groupInfoSection: some View {
        Section {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 56, height: 56)
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(group?.name ?? "")
                        .font(.headline)
                    if let g = group {
                        Text(String(localized: "dm.group.memberCount \(g.memberCount)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isOwner {
                    Button {
                        editedName = group?.name ?? ""
                        isEditingName = true
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
    }

    // MARK: - Members

    @ViewBuilder
    private var membersSection: some View {
        Section(String(localized: "dm.groupSettings.members")) {
            ForEach(convo.members) { member in
                HStack(spacing: 12) {
                    AvatarView(url: member.avatar, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(member.displayNameOrHandle)
                                .font(.callout)
                                .fontWeight(.medium)
                            if member.did == convo.members.first?.did {
                                Text(String(localized: "dm.groupSettings.owner"))
                                    .font(.caption2)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(.blue, in: Capsule())
                            }
                        }
                        Text("@\(member.handle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isOwner && member.did != myDID {
                        Button {
                            kickTarget = member
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if isOwner {
                Button {
                    showAddMembers = true
                } label: {
                    Label(String(localized: "dm.groupSettings.addMember"), systemImage: "plus.circle")
                }
            }
        }
    }

    // MARK: - Join Link

    @ViewBuilder
    private var joinLinkSection: some View {
        Section(String(localized: "dm.groupSettings.joinLink")) {
            if let joinLink = group?.joinLink, let code = joinLink.code {
                // リンク URL + コピー
                let linkURL = "https://bsky.app/chat/\(code)"
                HStack {
                    Text(linkURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = linkURL
                        showToast(String(localized: "profileQR.copiedToast"))
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                }

                // 有効 / 無効切替
                Toggle(String(localized: "dm.groupSettings.joinLinkEnabled"), isOn: .init(
                    get: { joinLink.isEnabled },
                    set: { enabled in
                        Task {
                            if enabled {
                                await enableJoinLink()
                            } else {
                                await disableJoinLink()
                            }
                        }
                    }
                ))
                .disabled(isJoinLinkOperating)

                // 参加ルール
                Picker(String(localized: "dm.groupSettings.joinRule"), selection: Binding(
                    get: { joinLink.joinRule ?? "anyone" },
                    set: { newValue in
                        Task { await editJoinLink(joinRule: newValue, requireApproval: nil) }
                    }
                )) {
                    Text(String(localized: "dm.groupSettings.joinRule.anyone")).tag("anyone")
                    Text(String(localized: "dm.groupSettings.joinRule.followedByOwner")).tag("followedByOwner")
                }
                .disabled(isJoinLinkOperating)

                // 承認必須
                Toggle(String(localized: "dm.groupSettings.requireApproval"), isOn: .init(
                    get: { joinLink.requireApproval == true },
                    set: { newValue in
                        Task { await editJoinLink(joinRule: nil, requireApproval: newValue) }
                    }
                ))
                .disabled(isJoinLinkOperating)

                if isJoinLinkOperating {
                    HStack { Spacer(); ProgressView().scaleEffect(0.8); Spacer() }
                }
            } else {
                Button {
                    Task { await createJoinLink() }
                } label: {
                    HStack {
                        Text(String(localized: "dm.groupSettings.createJoinLink"))
                        if isJoinLinkOperating {
                            Spacer()
                            ProgressView().scaleEffect(0.8)
                        }
                    }
                }
                .disabled(isJoinLinkOperating)
            }
        }
    }

    // MARK: - Join Requests

    @ViewBuilder
    private var joinRequestsSection: some View {
        Section(String(localized: "dm.groupSettings.joinRequests")) {
            if isLoadingRequests {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else {
                ForEach(joinRequests) { request in
                    HStack(spacing: 12) {
                        AvatarView(url: request.avatar, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(request.displayNameOrHandle)
                                .font(.callout)
                                .fontWeight(.medium)
                            Text("@\(request.handle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task { await approveRequest(request) }
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        Button {
                            Task { await rejectRequest(request) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Lock

    @ViewBuilder
    private var lockSection: some View {
        Section {
            Toggle(String(localized: "dm.groupSettings.lockToggle"), isOn: .init(
                get: { convo.isLocked },
                set: { locked in
                    Task {
                        if locked {
                            await lockGroup()
                        } else {
                            await unlockGroup()
                        }
                    }
                }
            ))
        } footer: {
            Text(String(localized: "dm.groupSettings.lockDescription"))
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionsSection: some View {
        Section {
            // ミュート
            Button {
                Task {
                    if convo.muted == true {
                        await unmuteGroup()
                    } else {
                        await muteGroup()
                    }
                }
            } label: {
                Label(
                    convo.muted == true ? String(localized: "dm.unmute") : String(localized: "dm.mute"),
                    systemImage: convo.muted == true ? "bell" : "bell.slash"
                )
            }

            // 退出
            Button(role: .destructive) {
                showLeaveConfirm = true
            } label: {
                Label(String(localized: "dm.leave"), systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }

    // MARK: - API Actions

    @MainActor private func updateGroupName() async {
        let name = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            convo = try await chatService.editGroup(convoId: convo.id, name: name)
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func kickMember(_ member: ChatMember) async {
        do {
            convo = try await chatService.removeMembers(convoId: convo.id, memberDIDs: [member.did])
            kickTarget = nil
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func leaveGroup() async {
        do {
            try await chatService.leaveConvo(convoId: convo.id)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func createJoinLink() async {
        isJoinLinkOperating = true
        do {
            convo = try await chatService.createJoinLink(convoId: convo.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isJoinLinkOperating = false
    }

    @MainActor private func editJoinLink(joinRule: String?, requireApproval: Bool?) async {
        isJoinLinkOperating = true
        do {
            convo = try await chatService.editJoinLink(convoId: convo.id, joinRule: joinRule, requireApproval: requireApproval)
        } catch {
            errorMessage = error.localizedDescription
        }
        isJoinLinkOperating = false
    }

    @MainActor private func enableJoinLink() async {
        isJoinLinkOperating = true
        do {
            convo = try await chatService.enableJoinLink(convoId: convo.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isJoinLinkOperating = false
    }

    @MainActor private func disableJoinLink() async {
        isJoinLinkOperating = true
        do {
            convo = try await chatService.disableJoinLink(convoId: convo.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isJoinLinkOperating = false
    }

    @MainActor private func lockGroup() async {
        do {
            convo = try await chatService.lockConvo(convoId: convo.id)
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func unlockGroup() async {
        do {
            convo = try await chatService.unlockConvo(convoId: convo.id)
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func muteGroup() async {
        do {
            convo = try await chatService.muteConvo(convoId: convo.id)
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func unmuteGroup() async {
        do {
            convo = try await chatService.unmuteConvo(convoId: convo.id)
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func loadJoinRequests() async {
        isLoadingRequests = true
        do {
            let response = try await chatService.listJoinRequests(convoId: convo.id)
            joinRequests = response.requests
            try await chatService.updateJoinRequestsRead(convoId: convo.id)
        } catch {
            // 参加申請読み込み失敗は無視
        }
        isLoadingRequests = false
    }

    @MainActor private func approveRequest(_ request: JoinRequestView) async {
        do {
            try await chatService.approveJoinRequest(convoId: convo.id, did: request.did)
            joinRequests.removeAll { $0.did == request.did }
            // convo を再取得してメンバー一覧を更新
            convo = try await chatService.getConvo(convoId: convo.id)
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func rejectRequest(_ request: JoinRequestView) async {
        do {
            try await chatService.rejectJoinRequest(convoId: convo.id, did: request.did)
            joinRequests.removeAll { $0.did == request.did }
        } catch { errorMessage = error.localizedDescription }
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { toastMessage = nil }
        }
    }
}

// MARK: - AddMembersSheet（メンバー追加シート）

struct AddMembersSheet: View {
    @Environment(AuthViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss

    let chatService: ChatService
    let convoId: String
    let onMembersAdded: (ConvoView) -> Void

    @State private var searchText = ""
    @State private var searchResults: [ProfileViewBasic] = []
    @State private var selectedDIDs: Set<String> = []
    @State private var isSearching = false
    @State private var isAdding = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                ForEach(searchResults, id: \.did) { actor in
                    let isSelected = selectedDIDs.contains(actor.did)
                    Button {
                        if isSelected {
                            selectedDIDs.remove(actor.did)
                        } else {
                            selectedDIDs.insert(actor.did)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(url: actor.avatar, size: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(actor.displayNameOrHandle)
                                    .font(.callout).fontWeight(.medium).foregroundStyle(.primary)
                                Text("@\(actor.handle)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                            }
                        }
                    }
                }

                if isSearching {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: String(localized: "dm.searchUser"))
            .onChange(of: searchText) { _, newValue in
                scheduleSearch(query: newValue)
            }
            .navigationTitle(String(localized: "dm.groupSettings.addMember"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await addMembers() }
                    } label: {
                        if isAdding { ProgressView().scaleEffect(0.8) }
                        else { Text(String(localized: "dm.groupSettings.addMember")).fontWeight(.semibold) }
                    }
                    .disabled(selectedDIDs.isEmpty || isAdding)
                }
            }
        }
    }

    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await performSearch(query: query)
        }
    }

    @MainActor private func performSearch(query: String) async {
        isSearching = true
        let svc = SearchService(client: authVM.client)
        do {
            let response = try await svc.searchActorsTypeahead(query: query, limit: 20)
            searchResults = response.actors.filter { $0.did != authVM.client.currentSession?.did }
        } catch { searchResults = [] }
        isSearching = false
    }

    @MainActor private func addMembers() async {
        guard !selectedDIDs.isEmpty else { return }
        isAdding = true
        do {
            let updated = try await chatService.addMembers(convoId: convoId, memberDIDs: Array(selectedDIDs))
            onMembersAdded(updated)
        } catch {}
        isAdding = false
    }
}
