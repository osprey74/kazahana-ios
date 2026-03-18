// ImageGridView.swift
// kazahana-ios
// 投稿内画像グリッド表示（タップでフルスクリーン ImageViewer を開く）

import SwiftUI

struct ImageGridView: View {

    let images: [EmbedImageView]

    @State private var selectedImageIndex: Int = 0
    @State private var isViewerPresented = false

    var body: some View {
        Group {
            switch images.count {
            case 1:
                singleImage(images[0], index: 0)
            case 2:
                HStack(spacing: 2) {
                    gridImage(images[0], index: 0)
                    gridImage(images[1], index: 1)
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            case 3:
                HStack(spacing: 2) {
                    gridImage(images[0], index: 0)
                    VStack(spacing: 2) {
                        gridImage(images[1], index: 1)
                        gridImage(images[2], index: 2)
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            case 4...:
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        gridImage(images[0], index: 0)
                        gridImage(images[1], index: 1)
                    }
                    HStack(spacing: 2) {
                        gridImage(images[2], index: 2)
                        gridImage(images[3], index: 3)
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            default:
                EmptyView()
            }
        }
        // isPresented を使うことで selectedIndex が変わっても閉じない
        .fullScreenCover(isPresented: $isViewerPresented) {
            ImageViewer(images: images, selectedIndex: $selectedImageIndex)
        }
    }

    // MARK: - Image cells

    private func singleImage(_ image: EmbedImageView, index: Int) -> some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .overlay {
                AsyncImage(url: URL(string: image.thumb)) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: placeholderRect
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .onTapGesture {
                selectedImageIndex = index
                isViewerPresented = true
            }
            .accessibilityLabel(image.alt.isEmpty ? "画像" : image.alt)
    }

    private func gridImage(_ image: EmbedImageView, index: Int) -> some View {
        Color.clear
            .overlay {
                AsyncImage(url: URL(string: image.thumb)) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        placeholderRect
                    }
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture {
                selectedImageIndex = index
                isViewerPresented = true
            }
            .accessibilityLabel(image.alt.isEmpty ? "画像" : image.alt)
    }

    private var placeholderRect: some View {
        Rectangle().fill(Color.secondary.opacity(0.2))
    }
}


