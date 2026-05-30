// LoginView.swift
// kazahana-ios
// ログイン画面

import SwiftUI

struct LoginView: View {

    @Environment(AuthViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss

    @State private var identifier: String = ""
    @State private var password: String = ""
    @State private var isPasswordVisible: Bool = false
    @State private var showHandleHistory: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // ロゴ・タイトル
                    VStack(spacing: 12) {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 18))

                        Text("kazahana")
                            .font(.largeTitle.bold())
                    }
                    .padding(.top, 60)

                    // 入力フォーム
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "auth.handle"))
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                            TextField("alice.bsky.social", text: $identifier)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.username)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .onTapGesture { showHandleHistory = true }
                                .onChange(of: identifier) { _, _ in showHandleHistory = true }

                            // ハンドル履歴サジェスト
                            if showHandleHistory {
                                let filtered = filteredHandleHistory
                                if !filtered.isEmpty {
                                    VStack(spacing: 0) {
                                        ForEach(filtered, id: \.self) { handle in
                                            HStack {
                                                Text("@\(handle)")
                                                    .font(.subheadline)
                                                Spacer()
                                                Button {
                                                    AppSettings.shared.removeHandleHistory(handle)
                                                } label: {
                                                    Image(systemName: "xmark")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 8)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                identifier = handle
                                                showHandleHistory = false
                                            }
                                            Divider()
                                        }
                                    }
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "auth.appPassword"))
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                            ZStack(alignment: .trailing) {
                                Group {
                                    if isPasswordVisible {
                                        TextField("xxxx-xxxx-xxxx-xxxx", text: $password)
                                            .textContentType(.password)
                                            .autocorrectionDisabled()
                                            .textInputAutocapitalization(.never)
                                    } else {
                                        SecureField("xxxx-xxxx-xxxx-xxxx", text: $password)
                                            .textContentType(.password)
                                    }
                                }
                                .textFieldStyle(.roundedBorder)
                                Button {
                                    isPasswordVisible.toggle()
                                } label: {
                                    Image(systemName: isPasswordVisible ? "eye" : "eye.slash")
                                        .foregroundStyle(isPasswordVisible ? Color.accentColor : Color.secondary)
                                }
                                .padding(.trailing, 8)
                            }
                        }

                        // エラーメッセージ
                        if let error = authVM.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // ログインボタン
                        Button {
                            Task {
                                await authVM.login(
                                    identifier: identifier.trimmingCharacters(in: .whitespaces).lowercased(),
                                    password: password.trimmingCharacters(in: .whitespaces).lowercased()
                                )
                                // シートとして表示されている場合は閉じる
                                if authVM.isLoggedIn { dismiss() }
                            }
                        } label: {
                            HStack {
                                if authVM.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.8)
                                }
                                Text(String(localized: "auth.login"))
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(authVM.isLoading || identifier.isEmpty || password.isEmpty)
                    }
                    .padding(.horizontal, 24)

                    Spacer()
                }
            }
            .toolbar {
                // sheet として表示された場合のみ閉じるボタンを表示
                if isPresented {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "common.close")) {
                            dismiss()
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// sheet として表示されているかを判定（保存済みアカウントがある＝ルートではない）
    private var isPresented: Bool {
        !authVM.savedAccounts.isEmpty
    }

    /// 入力にマッチするハンドル履歴（空入力時は全件）
    private var filteredHandleHistory: [String] {
        let history = AppSettings.shared.handleHistory
        if identifier.isEmpty { return history }
        return history.filter { $0.localizedCaseInsensitiveContains(identifier) }
    }
}

#Preview {
    LoginView()
        .environment(AuthViewModel())
}
