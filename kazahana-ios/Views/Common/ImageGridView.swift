// ImageGridView.swift
// kazahana-ios
// 投稿内画像グリッド表示（タップでフルスクリーン ImageViewer を開く）

import SwiftUI

struct ImageGridView: View {

    let images: [EmbedImageView]

    @State private var selectedImageIndex: Int = 0
    @State private var isViewerPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                switch images.count {
                case 1:
                    singleImage(images[0], index: 0)
                case 2:
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 2) {
                            gridImage(images[0], index: 0)
                            gridImage(images[1], index: 1)
                        }
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        multiAltTextLabels(images: Array(images.prefix(2)))
                    }
                case 3:
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 2) {
                            gridImage(images[0], index: 0)
                            VStack(spacing: 2) {
                                gridImage(images[1], index: 1)
                                gridImage(images[2], index: 2)
                            }
                        }
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        multiAltTextLabels(images: Array(images.prefix(3)))
                    }
                case 4...:
                    VStack(alignment: .leading, spacing: 4) {
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

                        multiAltTextLabels(images: Array(images.prefix(4)))
                    }
                default:
                    EmptyView()
                }
            }
        }
        // isPresented を使うことで selectedIndex が変わっても閉じない
        .fullScreenCover(isPresented: $isViewerPresented) {
            ImageViewer(images: images, selectedIndex: $selectedImageIndex)
        }
    }

    // MARK: - Image cells

    private func singleImage(_ image: EmbedImageView, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let ar = image.aspectRatio, ar.height > 0 {
                // アスペクト比が既知の場合: 実際の比率で表示（縦長は最大400ptでキャップ）
                let ratio = CGFloat(ar.width) / CGFloat(ar.height)
                AsyncImage(url: URL(string: image.thumb)) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFit()
                    default:
                        placeholderRect.aspectRatio(ratio, contentMode: .fit)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 400)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedImageIndex = index
                    isViewerPresented = true
                }
                .accessibilityLabel(image.alt.isEmpty ? String(localized: "image.accessibility") : image.alt)
            } else {
                // アスペクト比不明の場合: 従来通り固定高さ + scaledToFill
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
                    .accessibilityLabel(image.alt.isEmpty ? String(localized: "image.accessibility") : image.alt)
            }

            if !image.alt.isEmpty {
                altTextLabel(image.alt)
            }
        }
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
            .accessibilityLabel(image.alt.isEmpty ? String(localized: "image.accessibility") : image.alt)
    }

    /// ALT テキストを先頭 128 文字まで表示（超過分は「…」）
    private func altTextLabel(_ alt: String) -> some View {
        let truncated = alt.count > 128 ? String(alt.prefix(128)) + "…" : alt
        return Text(truncated)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 複数画像のうち ALT テキストが設定されているものを [1] [2] … 形式で表示
    @ViewBuilder
    private func multiAltTextLabels(images: [EmbedImageView]) -> some View {
        let alts = images.enumerated().compactMap { (i, img) -> String? in
            guard !img.alt.isEmpty else { return nil }
            let truncated = img.alt.count > 128 ? String(img.alt.prefix(128)) + "…" : img.alt
            return "[\(i + 1)] \(truncated)"
        }
        if !alts.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(alts, id: \.self) { line in
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var placeholderRect: some View {
        Rectangle().fill(Color.secondary.opacity(0.2))
    }
}


