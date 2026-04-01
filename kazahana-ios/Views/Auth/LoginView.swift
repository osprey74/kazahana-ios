// LoginView.swift
// kazahana-ios
// ログイン画面

import SwiftUI

struct LoginView: View {

    @Environment(AuthViewModel.self) private var authVM

    @State private var identifier: String = ""
    @State private var password: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // ロゴ・タイトル
                    VStack(spacing: 12) {
                        Image(systemName: "wind")
                            .font(.system(size: 60))
                            .foregroundStyle(Color.accentColor)

                        Text("kazahana")
                            .font(.largeTitle.bold())

                        Text(String(localized: "auth.tagline"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "auth.appPassword"))
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                            SecureField("xxxx-xxxx-xxxx-xxxx", text: $password)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.password)
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

                    // アプリパスワード注意
                    VStack(spacing: 8) {
                        Text(String(localized: "auth.appPassword"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(String(localized: "auth.helpText"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)

                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
    }
}

#Preview {
    LoginView()
        .environment(AuthViewModel())
}
