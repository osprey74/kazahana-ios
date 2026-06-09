// GalleryCarouselView.swift
// kazahana-ios
// 5枚以上の画像をカルーセル（横スクロール）で表示（app.bsky.embed.gallery 対応）

import SwiftUI

struct GalleryCarouselView: View {

    let images: [EmbedImageView]
    var maxWidth: CGFloat? = nil

    @State private var selectedIndex: Int = 0
    @State private var isViewerPresented = false

    private var carouselHeight: CGFloat {
        guard let w = maxWidth else { return 280 }
        return max(120, 280 * (w / 360))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                TabView(selection: $selectedIndex) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                        carouselImage(image, index: index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
                .frame(height: carouselHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // 枚数バッジ（"3 / 7"）
                Text("\(selectedIndex + 1) / \(images.count)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6), in: Capsule())
                    .padding(8)
            }

            // 現在表示中の画像の ALT テキスト
            if selectedIndex < images.count, !images[selectedIndex].alt.isEmpty {
                let alt = images[selectedIndex].alt
                let truncated = alt.count > 128 ? String(alt.prefix(128)) + "…" : alt
                Text("[\(selectedIndex + 1)] \(truncated)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: maxWidth ?? .infinity, alignment: .leading)
        .fullScreenCover(isPresented: $isViewerPresented) {
            ImageViewer(images: images, selectedIndex: $selectedIndex)
        }
    }

    private func carouselImage(_ image: EmbedImageView, index: Int) -> some View {
        Color.clear
            .overlay {
                AsyncImage(url: URL(string: image.thumb)) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        Rectangle().fill(Color.secondary.opacity(0.2))
                    }
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture {
                if AppSettings.shared.imageOpenMode == .external {
                    if let url = URL(string: image.fullsize) {
                        UIApplication.shared.open(url)
                    }
                } else {
                    selectedIndex = index
                    isViewerPresented = true
                }
            }
            .accessibilityLabel(image.alt.isEmpty ? String(localized: "image.accessibility") : image.alt)
    }
}
