// AnimatedImageView.swift
// kazahana-ios
// アニメーション GIF 対応の画像表示ビュー（ImageIO 使用、外部依存なし）

import SwiftUI
import ImageIO
import UIKit

/// URL から画像データをダウンロードし、GIF ならアニメーション再生、それ以外は静止表示する。
/// URLSession の標準キャッシュを活用するため、同一 URL の再ダウンロードは抑制される。
struct AnimatedImageView: View {
    let url: URL?
    var contentMode: UIView.ContentMode = .scaleAspectFit

    @State private var phase: LoadPhase = .loading

    private enum LoadPhase {
        case loading
        case loaded(UIImage, isAnimated: Bool)
        case failed
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .loaded(let image, let isAnimated):
                if isAnimated {
                    AnimatedUIImageView(image: image, contentMode: contentMode)
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode == .scaleAspectFill ? .fill : .fit)
                }
            case .failed:
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url else {
            phase = .failed
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if isGIFData(data), let animatedImage = createAnimatedImage(from: data) {
                phase = .loaded(animatedImage, isAnimated: true)
            } else if let image = UIImage(data: data) {
                phase = .loaded(image, isAnimated: false)
            } else {
                phase = .failed
            }
        } catch {
            if !Task.isCancelled {
                phase = .failed
            }
        }
    }
}

// MARK: - GIF 判定・フレーム抽出

private func isGIFData(_ data: Data) -> Bool {
    guard data.count >= 6 else { return false }
    // GIF87a or GIF89a
    return data.starts(with: [0x47, 0x49, 0x46, 0x38])
}

/// ImageIO で GIF の全フレームを抽出し、UIImage.animatedImage を生成する
private func createAnimatedImage(from data: Data) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let count = CGImageSourceGetCount(source)
    guard count > 1 else { return nil }

    var frames: [UIImage] = []
    var totalDuration: Double = 0
    frames.reserveCapacity(count)

    for i in 0..<count {
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
        frames.append(UIImage(cgImage: cgImage))
        totalDuration += frameDuration(at: i, source: source)
    }

    guard !frames.isEmpty else { return nil }
    if totalDuration <= 0 { totalDuration = Double(frames.count) * 0.1 }
    return UIImage.animatedImage(with: frames, duration: totalDuration)
}

/// GIF フレームの表示時間を取得する
private func frameDuration(at index: Int, source: CGImageSource) -> Double {
    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
          let gifDict = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
        return 0.1
    }
    // UnclampedDelayTime → DelayTime の順で取得
    if let delay = gifDict[kCGImagePropertyGIFUnclampedDelayTime] as? Double, delay > 0 {
        return delay
    }
    if let delay = gifDict[kCGImagePropertyGIFDelayTime] as? Double, delay > 0 {
        return delay
    }
    return 0.1
}

// MARK: - UIImageView ラッパー（GIF アニメーション再生用）

private struct AnimatedUIImageView: UIViewRepresentable {
    let image: UIImage
    var contentMode: UIView.ContentMode = .scaleAspectFit

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = contentMode
        imageView.clipsToBounds = true
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        uiView.contentMode = contentMode
        if uiView.image !== image {
            uiView.image = image
            uiView.animationImages = image.images
            uiView.animationDuration = image.duration
            uiView.startAnimating()
        }
    }
}
