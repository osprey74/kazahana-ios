// ContentWarningView.swift
// kazahana-ios
// モデレーション警告オーバーレイ（投稿全体ブラー / メディアブラー）

import SwiftUI

// MARK: - 投稿全体ブラー

/// 投稿全体を覆い「表示する」ボタンで一時的に解除できるオーバーレイ
struct PostBlurOverlay: View {
    let message: String?
    @State private var isRevealed = false

    var body: some View {
        if !isRevealed {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "eye.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(message ?? String(localized: "moderation.contentWarning"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(String(localized: "moderation.show")) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRevealed = true
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer()
            }
            .padding(.vertical, 24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        } else {
            HStack {
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isRevealed = false
                    }
                } label: {
                    Label(String(localized: "moderation.hide"), systemImage: "eye.slash")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - メディアブラー

/// 画像・動画などメディアの上に重ねるブラーオーバーレイ
struct MediaBlurOverlay: View {
    let message: String?
    @State private var isRevealed = false

    var body: some View {
        if !isRevealed {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)

                VStack(spacing: 6) {
                    Image(systemName: "eye.slash")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    if let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button(String(localized: "moderation.show")) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRevealed = true
                        }
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            VStack {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRevealed = false
                        }
                    } label: {
                        Image(systemName: "eye.slash")
                            .font(.caption2)
                            .padding(5)
                            .background(.regularMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }
                Spacer()
            }
        }
    }
}
