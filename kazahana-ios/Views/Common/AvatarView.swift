// AvatarView.swift
// kazahana-ios
// アバター画像表示コンポーネント（AsyncImage を使用）

import SwiftUI

struct AvatarView: View {

    let url: String?
    var size: CGFloat = 44

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
