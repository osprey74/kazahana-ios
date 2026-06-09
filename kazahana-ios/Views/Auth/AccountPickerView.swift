// AccountPickerView.swift
// kazahana-ios
// 起動時・設定画面から呼び出されるアカウント選択画面

import SwiftUI

struct AccountPickerView: View {

    @Environment(AuthViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss
    /// sheet として表示されている場合に true にすると閉じるボタンを表示
    var showCloseButton: Bool = false
    @State private var showLogin = false
    @State private var removeTarget: Session? = nil

    var body: some View {
        NavigationStack {
            List {
                ForEach(authVM.savedAccounts, id: \.did) { session in
                    accountRow(session: session)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !authVM.isSwitchingAccount else { return }
                            Task { await authVM.switchAccount(to: session) }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                removeTarget = session
                            } label: {
                                Label(String(localized: "auth.accountPicker.removeAccount"), systemImage: "trash")
                            }
                        }
                }

                Button {
                    showLogin = true
                } label: {
                    Label(String(localized: "auth.accountPicker.addAccount"), systemImage: "plus.circle")
                }
            }
            .listStyle(.insetGrouped)
            .toolbar(showCloseButton ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                if showCloseButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "common.close")) {
                            dismiss()
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 12) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    Text("kazahana")
                        .font(.largeTitle.bold())
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 52)
                .padding(.bottom, 20)
                .background(Color(.systemGroupedBackground))
            }
        }
        .overlay {
            if authVM.isSwitchingAccount {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.3)
                        .tint(.white)
                    Text(String(localized: "auth.switchingAccount"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
                .background(.ultraThinMaterial.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .allowsHitTesting(!authVM.isSwitchingAccount)
        .sheet(isPresented: $showLogin) {
            LoginView()
                .environment(authVM)
        }
        .confirmationDialog(
            String(localized: "auth.accountPicker.removeConfirmTitle"),
            isPresented: Binding(
                get: { removeTarget != nil },
                set: { if !$0 { removeTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "auth.accountPicker.removeAccount"), role: .destructive) {
                if let session = removeTarget {
                    Task { await authVM.removeAccount(did: session.did) }
                    removeTarget = nil
                }
            }
            Button(String(localized: "common.cancel"), role: .cancel) { removeTarget = nil }
        } message: {
            Text(String(localized: "auth.accountPicker.removeConfirmMessage"))
        }
    }

    @ViewBuilder
    private func accountRow(session: Session) -> some View {
        HStack(spacing: 14) {
            // アバタープレースホルダー
            Circle()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 46, height: 46)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text("@\(session.handle)")
                    .font(.headline)
                    .lineLimit(1)
                Text(session.did)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "arrow.right.circle")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    AccountPickerView()
        .environment(AuthViewModel())
}
