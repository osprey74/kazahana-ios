// ImageViewer.swift
// kazahana-ios
// 画像フルスクリーン表示（ピンチズーム + 複数枚スワイプ）

import SwiftUI

struct ImageViewer: View {

    let images: [EmbedImageView]
    @Binding var selectedIndex: Int
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    /// 現在表示中の画像の ALT テキスト
    private var currentAlt: String {
        guard selectedIndex < images.count else { return "" }
        return images[selectedIndex].alt
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // ページングスクロール
                TabView(selection: $selectedIndex) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                        ZoomableImage(urlString: image.fullsize, alt: image.alt)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                // ALT テキスト（ページインジケーターの下に配置）
                if !currentAlt.isEmpty {
                    ScrollView {
                        Text(currentAlt)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 100)
                    .background(Color.black.opacity(0.6))
                }
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
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear {
            isFocused = true
            // 前後の画像をプリフェッチして表示遅延を防止
            prefetchImages()
        }
        .onChange(of: selectedIndex) { _, _ in
            prefetchImages()
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .escape]) { press in
            switch press.key {
            case .leftArrow:
                if selectedIndex > 0 { withAnimation { selectedIndex -= 1 } }
                return .handled
            case .rightArrow:
                if selectedIndex < images.count - 1 { withAnimation { selectedIndex += 1 } }
                return .handled
            case .escape:
                dismiss()
                return .handled
            default:
                return .ignored
            }
        }
    }

    /// 現在ページの前後2枚をプリフェッチ（AsyncImage のキャッシュに載せる）
    private func prefetchImages() {
        let range = max(0, selectedIndex - 1)...min(images.count - 1, selectedIndex + 2)
        for i in range where i != selectedIndex {
            guard let url = URL(string: images[i].fullsize) else { continue }
            // URLSession の共有キャッシュに載せる（AsyncImage はこのキャッシュを参照する）
            let request = URLRequest(url: url)
            if URLCache.shared.cachedResponse(for: request) == nil {
                Task {
                    _ = try? await URLSession.shared.data(for: request)
                }
            }
        }
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
    @State private var imageSize: CGSize = .zero

    /// ズーム中かどうか（TabView のスワイプ制御に使用）
    private var isZoomed: Bool { scale > 1.0 }

    /// ズーム時に画像がコンテナ外へはみ出せる最大オフセットを計算
    private func clampedOffset(_ proposed: CGSize, in containerSize: CGSize) -> CGSize {
        guard scale > 1.0 else { return .zero }
        let scaledW = imageSize.width * scale
        let scaledH = imageSize.height * scale
        let maxX = max(0, (scaledW - containerSize.width) / 2)
        let maxY = max(0, (scaledH - containerSize.height) / 2)
        return CGSize(
            width: min(maxX, max(-maxX, proposed.width)),
            height: min(maxY, max(-maxY, proposed.height))
        )
    }

    /// ピンチズームジェスチャー（常時有効）
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(1.0, min(lastScale * value, 5.0))
            }
            .onEnded { _ in
                if scale <= 1.0 {
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
    }

    /// ズーム中のドラッグ（パン）ジェスチャー（拡大時のみ有効）
    private func dragGesture(in containerSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let proposed = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = proposed
            }
            .onEnded { _ in
                let clamped = clampedOffset(offset, in: containerSize)
                if clamped != offset {
                    withAnimation(.spring(duration: 0.3)) { offset = clamped }
                }
                lastOffset = clamped
            }
    }

    var body: some View {
        GeometryReader { geo in
            AsyncImage(url: URL(string: urlString)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .background(GeometryReader { imgGeo in
                            Color.clear.onAppear { imageSize = imgGeo.size }
                        })
                        .scaleEffect(scale)
                        .offset(offset)
                        // ピンチズームは常時有効
                        .gesture(magnificationGesture)
                        // ドラッグはズーム中のみ有効（等倍時は TabView のスワイプに委譲）
                        .simultaneousGesture(
                            dragGesture(in: geo.size),
                            isEnabled: isZoomed
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
