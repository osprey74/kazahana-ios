// GroupJoinView.swift
// kazahana-ios
// グループ招待リンクからの参加画面

import SwiftUI

struct GroupJoinView: View {
    @Environment(AuthViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss

    let code: String

    @State private var preview: JoinLinkPreviewActive?
    @State private var isLoading = true
    @State private var isJoining = false
    @State private var errorMessage: String?
    @State private var linkDisabled = false
    @State private var linkInvalid = false
    @State private var joinedConvo: ConvoView?
    @State private var isPending = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if linkDisabled {
                    errorState(
                        icon: "link.badge.plus",
                        message: String(localized: "dm.joinLink.disabled")
                    )
                } else if linkInvalid {
                    errorState(
                        icon: "exclamationmark.triangle",
                        message: String(localized: "dm.joinLink.invalid")
                    )
                } else if isPending {
                    pendingState
                } else if let preview {
                    previewContent(preview)
                }
            }
            .navigationTitle(String(localized: "dm.groupJoin.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                }
            }
            .alert(String(localized: "dm.groupJoin.error"), isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button(String(localized: "common.ok")) { errorMessage = nil }
            } message: {
                if let msg = errorMessage { Text(msg) }
            }
        }
        .task {
            await loadPreview()
        }
    }

    // MARK: - Preview Content

    @ViewBuilder
    private func previewContent(_ preview: JoinLinkPreviewActive) -> some View {
        VStack(spacing: 24) {
            Spacer()

            // グループアイコン
            ZStack {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 80, height: 80)
                Image(systemName: "person.3.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
            }

            // グループ情報
            VStack(spacing: 8) {
                if let name = preview.name {
                    Text(name)
                        .font(.title2)
                        .fontWeight(.bold)
                }
                if let count = preview.memberCount {
                    Text(String(localized: "dm.joinLink.memberCount \(count)"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let owner = preview.owner {
                    HStack(spacing: 6) {
                        AvatarView(url: owner.avatar, size: 20)
                        Text(String(localized: "dm.joinLink.ownerLabel \(owner.displayNameOrHandle)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // 参加ボタン
            Button {
                Task { await joinGroup() }
            } label: {
                if isJoining {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                } else {
                    Text(String(localized: "dm.groupJoin.join"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isJoining)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Pending State

    private var pendingState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text(String(localized: "dm.groupJoin.pending"))
                .font(.headline)
            Text(String(localized: "dm.groupJoin.pendingDescription"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button(String(localized: "common.ok")) { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
        }
    }

    // MARK: - Error State

    @ViewBuilder
    private func errorState(icon: String, message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button(String(localized: "common.ok")) { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
        }
    }

    // MARK: - Actions

    private func loadPreview() async {
        isLoading = true
        do {
            let chatService = ChatService(client: authVM.client)
            let response = try await chatService.getJoinLinkPreviews(codes: [code])
            if let first = response.joinLinkPreviews.first {
                switch first {
                case .active(let active):
                    preview = active
                case .disabled:
                    linkDisabled = true
                case .invalid:
                    linkInvalid = true
                }
            } else {
                linkInvalid = true
            }
        } catch {
            print("[GroupJoinView] getJoinLinkPreviews error: \(error)")
            errorMessage = error.localizedDescription
            linkInvalid = true
        }
        isLoading = false
    }

    private func joinGroup() async {
        isJoining = true
        do {
            let chatService = ChatService(client: authVM.client)
            let response = try await chatService.requestJoin(code: code)
            if response.status == "joined" {
                // 即座に参加完了 — 閉じる（会話一覧のポーリングで反映される）
                dismiss()
            } else {
                // pending — 承認待ち状態を表示
                isPending = true
            }
        } catch {
            errorMessage = mapJoinError(error)
        }
        isJoining = false
    }

    private func mapJoinError(_ error: Error) -> String {
        let desc = error.localizedDescription
        if desc.contains("ConvoLocked") { return String(localized: "dm.groupJoin.error.locked") }
        if desc.contains("InvalidCode") { return String(localized: "dm.joinLink.invalid") }
        if desc.contains("LinkDisabled") { return String(localized: "dm.joinLink.disabled") }
        if desc.contains("MemberLimitReached") { return String(localized: "dm.groupJoin.error.full") }
        if desc.contains("UserKicked") { return String(localized: "dm.groupJoin.error.kicked") }
        if desc.contains("FollowRequired") { return String(localized: "dm.groupJoin.error.followRequired") }
        return desc
    }
}
