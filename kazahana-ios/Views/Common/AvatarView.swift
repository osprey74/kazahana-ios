// AvatarView.swift
// kazahana-ios
// アバター画像表示コンポーネント（AsyncImage を使用）

import SwiftUI

struct AvatarView: View {

    let url: String?
    var size: CGFloat = 44
    /// アバター右上にサポーターバッジ（勲章アイコン）を表示するか
    var showSupporterBadge: Bool = false

    var body: some View {
        Group {
            if let urlString = url, let imageURL = URL(string: urlString) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure, .empty:
                        placeholderView
                    @unknown default:
                        placeholderView
                    }
                }
            } else {
                placeholderView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(alignment: .topTrailing) {
            if showSupporterBadge {
                Image(systemName: "medal.fill")
                    .font(.system(size: size * 0.35))
                    .foregroundStyle(.yellow)
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                    .offset(x: size * 0.1, y: -(size * 0.1))
            }
        }
    }

    private var placeholderView: some View {
        Circle()
            .fill(Color.secondary.opacity(0.3))
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(Color.secondary)
            }
    }
}

#Preview {
    AvatarView(url: nil, size: 44)
}
