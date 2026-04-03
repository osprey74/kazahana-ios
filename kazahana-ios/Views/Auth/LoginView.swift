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
            .navigationBarHidden(true)
        }
    }
}

#Preview {
    LoginView()
        .environment(AuthViewModel())
}
