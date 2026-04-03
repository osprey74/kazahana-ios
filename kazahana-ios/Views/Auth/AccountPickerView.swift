// AccountPickerView.swift
// kazahana-ios
// 起動時・設定画面から呼び出されるアカウント選択画面

import SwiftUI

struct AccountPickerView: View {

    @Environment(AuthViewModel.self) private var authVM
    @State private var showLogin = false
    @State private var removeTarget: Session? = nil

    var body: some View {
        NavigationStack {
            List {
                ForEach(authVM.savedAccounts, id: \.did) { session in
                    accountRow(session: session)
                        .contentShape(Rectangle())
                        .onTapGesture {
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
            .toolbar(.hidden, for: .navigationBar)
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
