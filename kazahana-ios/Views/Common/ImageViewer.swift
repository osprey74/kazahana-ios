// ImageViewer.swift
// kazahana-ios
// 画像フルスクリーン表示（ピンチズーム + 複数枚スワイプ）

import SwiftUI

struct ImageViewer: View {

    let images: [EmbedImageView]
    @Binding var selectedIndex: Int
    @Environment(\.dismiss) private var dismiss

    /// 現在表示中の画像の ALT テキスト
    private var currentAlt: String {
        guard selectedIndex < images.count else { return "" }
        return images[selectedIndex].alt
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            // ページングスクロール
            TabView(selection: $selectedIndex) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    ZoomableImage(urlString: image.fullsize, alt: image.alt)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            // ALT テキスト（下部に最大3行、スクロール可能）
            if !currentAlt.isEmpty {
                VStack {
                    Spacer()
                    ScrollView {
                        Text(currentAlt)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 100)
                    .background(.ultraThinMaterial.opacity(0.8))
                }
                .ignoresSafeArea(edges: .bottom)
            }

            // 閉じるボタン（シャドウで背景色に依らず視認性を確保）
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 1)
                    .padding(16)
            }
        }
        .statusBarHidden(true)
    }
}

// MARK: - ピンチズーム対応画像

private struct ZoomableImage: View {

    let urlString: String
    let alt: String

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            AsyncImage(url: URL(string: urlString)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            // ピンチズームジェスチャー（TabView スワイプと競合しない）
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = max(1.0, lastScale * value)
                                }
                                .onEnded { _ in
                                    if scale < 1.0 {
                                        withAnimation(.spring(duration: 0.3)) {
                                            scale = 1.0
                                            offset = .zero
                                        }
                                        lastScale = 1.0
                                        lastOffset = .zero
                                    } else {
                                        lastScale = scale
                                    }
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(duration: 0.3)) {
                                if scale > 1.0 {
                                    scale = 1.0
                                    lastScale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2.5
                                    lastScale = 2.5
                                }
                            }
                        }
                        .accessibilityLabel(alt.isEmpty ? "画像" : alt)
                case .failure:
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .frame(width: geo.size.width, height: geo.size.height)
                case .empty:
                    ProgressView()
                        .frame(width: geo.size.width, height: geo.size.height)
                @unknown default:
                    EmptyView()
                }
            }
        }
    }
}
