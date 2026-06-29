// ImageCropView.swift
// Share​Extension
// 画像クロップエディタ（フルスクリーンカバー）

import SwiftUI
import UIKit

// MARK: - アスペクト比モード

enum CropAspectMode: String, CaseIterable, Identifiable {
    case original = "original"
    case square   = "square"
    case freeform = "freeform"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original: return String(localized: "crop.aspectOriginal")
        case .square:   return String(localized: "crop.aspectSquare")
        case .freeform: return String(localized: "crop.aspectFreeform")
        }
    }

    var icon: String {
        switch self {
        case .original: return "rectangle.on.rectangle"
        case .square:   return "square"
        case .freeform: return "rectangle.dashed"
        }
    }
}

// MARK: - クロップハンドル

private enum CropHandle {
    case topLeft, topRight, bottomLeft, bottomRight
    case topCenter, bottomCenter, leftCenter, rightCenter
    case move
}

// MARK: - ImageCropView

struct ImageCropView: View {

    let image: UIImage
    let onCrop: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var cropRect: CGRect = .zero
    @State private var aspectMode: CropAspectMode = .freeform

    @State private var rotationDegrees: Int = 0

    @State private var normalizedBase: UIImage = UIImage()
    @State private var displayImage: UIImage = UIImage()

    private var currentDisplayImage: UIImage {
        displayImage.size.width > 0 ? displayImage : image
    }

    @State private var activeHandle: CropHandle? = nil
    @State private var dragStartLocation: CGPoint = .zero
    @State private var dragStartCropRect: CGRect = .zero

    @State private var imageDisplayRect: CGRect = .zero

    private let minCropSize: CGFloat = 50
    private let handleHitRadius: CGFloat = 22

    private var rotatedImageSize: CGSize {
        let isTransposed = rotationDegrees == 90 || rotationDegrees == 270
        return isTransposed
            ? CGSize(width: image.size.height, height: image.size.width)
            : image.size
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                toolbar

                Spacer(minLength: 0)

                cropEditor
                    .layoutPriority(1)

                Spacer(minLength: 0)

                rotationBar

                aspectSelector
            }
        }
        .onAppear {
            let base = normalizeOrientation(image)
            normalizedBase = base
            displayImage = base
            resetCropRect()
        }
    }

    // MARK: - 上部ツールバー

    private var toolbar: some View {
        HStack {
            Button(String(localized: "crop.cancel")) {
                dismiss()
            }
            .foregroundStyle(.white)
            .padding(.leading, 20)

            Spacer()

            Button(String(localized: "crop.done")) {
                if let cropped = applyCrop() {
                    onCrop(cropped)
                }
                dismiss()
            }
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .padding(.trailing, 20)
        }
        .frame(height: 56)
    }

    // MARK: - クロップエディタ

    private var cropEditor: some View {
        GeometryReader { geo in
            let (scale, origin) = imageLayoutMetrics(in: geo.size)
            let imgSize = rotatedImageSize
            let imgRect = CGRect(
                x: origin.x, y: origin.y,
                width: imgSize.width * scale,
                height: imgSize.height * scale
            )

            ZStack {
                Image(uiImage: currentDisplayImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imgRect.width, height: imgRect.height)
                    .position(x: imgRect.midX, y: imgRect.midY)

                cropOverlay(imageRect: imgRect, scale: scale)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDragChanged(value: value, imageRect: imgRect, scale: scale)
                    }
                    .onEnded { _ in
                        activeHandle = nil
                    }
            )
            .onAppear {
                imageDisplayRect = imgRect
            }
            .onChange(of: geo.size) { _, newSize in
                let (s, o) = imageLayoutMetrics(in: newSize)
                let sz = rotatedImageSize
                imageDisplayRect = CGRect(
                    x: o.x, y: o.y,
                    width: sz.width * s,
                    height: sz.height * s
                )
            }
        }
    }

    // MARK: - クロップオーバーレイ描画

    @ViewBuilder
    private func cropOverlay(imageRect: CGRect, scale: CGFloat) -> some View {
        let screenCropRect = toScreenRect(cropRect, scale: scale, imageOrigin: imageRect.origin)

        Canvas { context, size in
            var outerPath = Path(CGRect(origin: .zero, size: size))
            outerPath.addRect(screenCropRect)
            context.fill(outerPath, with: .color(.black.opacity(0.5)), style: .init(eoFill: true))

            context.stroke(
                Path(screenCropRect),
                with: .color(.white),
                lineWidth: 1.5
            )

            var gridPath = Path()
            for i in 1...2 {
                let x = screenCropRect.minX + screenCropRect.width * CGFloat(i) / 3
                gridPath.move(to: CGPoint(x: x, y: screenCropRect.minY))
                gridPath.addLine(to: CGPoint(x: x, y: screenCropRect.maxY))
            }
            for i in 1...2 {
                let y = screenCropRect.minY + screenCropRect.height * CGFloat(i) / 3
                gridPath.move(to: CGPoint(x: screenCropRect.minX, y: y))
                gridPath.addLine(to: CGPoint(x: screenCropRect.maxX, y: y))
            }
            context.stroke(gridPath, with: .color(.white.opacity(0.4)), lineWidth: 0.5)

            let handleLen: CGFloat = 20
            let handleWidth: CGFloat = 3
            let corners: [(CGPoint, Bool, Bool)] = [
                (CGPoint(x: screenCropRect.minX, y: screenCropRect.minY), true, true),
                (CGPoint(x: screenCropRect.maxX, y: screenCropRect.minY), false, true),
                (CGPoint(x: screenCropRect.minX, y: screenCropRect.maxY), true, false),
                (CGPoint(x: screenCropRect.maxX, y: screenCropRect.maxY), false, false),
            ]
            for (pt, isLeft, isTop) in corners {
                var p = Path()
                let hx: CGFloat = isLeft ? 1 : -1
                let vy: CGFloat = isTop  ? 1 : -1
                p.move(to: pt)
                p.addLine(to: CGPoint(x: pt.x + hx * handleLen, y: pt.y))
                p.move(to: pt)
                p.addLine(to: CGPoint(x: pt.x, y: pt.y + vy * handleLen))
                context.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: handleWidth, lineCap: .round))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    // MARK: - 回転バー

    private var rotationBar: some View {
        HStack(spacing: 0) {
            Button {
                rotate(by: -90)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "rotate.left")
                        .font(.system(size: 22))
                    Text(String(localized: "crop.rotateLeft"))
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(.white.opacity(0.8))
            }

            Spacer()

            Text("\(rotationDegrees)°")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.5))
                .frame(minWidth: 44)

            Spacer()

            Button {
                rotate(by: 90)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "rotate.right")
                        .font(.system(size: 22))
                    Text(String(localized: "crop.rotateRight"))
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 40)
        .frame(height: 64)
    }

    private func rotate(by delta: Int) {
        rotationDegrees = ((rotationDegrees + delta) % 360 + 360) % 360
        displayImage = rotationDegrees == 0
            ? normalizedBase
            : applyRotation(to: normalizedBase, degrees: rotationDegrees)
        resetCropRect()
    }

    private func resetCropRect() {
        let w = rotatedImageSize.width
        let h = rotatedImageSize.height
        let inset = min(w, h) * 0.04
        cropRect = CGRect(x: inset, y: inset, width: w - inset * 2, height: h - inset * 2)
    }

    // MARK: - 下部アスペクト比セレクター

    private var aspectSelector: some View {
        HStack(spacing: 0) {
            ForEach(CropAspectMode.allCases) { mode in
                Button {
                    applyAspectMode(mode)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 22))
                        Text(mode.displayName)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(aspectMode == mode ? .white : .white.opacity(0.5))
                }
            }
        }
        .frame(height: 72)
    }

    // MARK: - ジェスチャー処理

    private func handleDragChanged(value: DragGesture.Value, imageRect: CGRect, scale: CGFloat) {
        if activeHandle == nil {
            let screenCropRect = toScreenRect(cropRect, scale: scale, imageOrigin: imageRect.origin)
            activeHandle = detectHandle(at: value.startLocation, cropScreenRect: screenCropRect)
            dragStartLocation = value.startLocation
            dragStartCropRect = cropRect
        }

        guard let handle = activeHandle else { return }

        let delta = CGPoint(
            x: value.location.x - dragStartLocation.x,
            y: value.location.y - dragStartLocation.y
        )
        let imgDelta = CGPoint(x: delta.x / scale, y: delta.y / scale)

        var newRect = dragStartCropRect
        let imageBounds = CGRect(origin: .zero, size: rotatedImageSize)

        switch handle {
        case .move:
            newRect.origin.x += imgDelta.x
            newRect.origin.y += imgDelta.y
            newRect = clampRect(newRect, to: imageBounds, preserveSize: true)

        case .topLeft:
            newRect.origin.x += imgDelta.x
            newRect.origin.y += imgDelta.y
            newRect.size.width  -= imgDelta.x
            newRect.size.height -= imgDelta.y
            newRect = applyAspectConstraint(newRect, anchorCorner: .bottomRight, original: dragStartCropRect)
            newRect = clampRect(newRect, to: imageBounds, preserveSize: false)

        case .topRight:
            newRect.origin.y += imgDelta.y
            newRect.size.width  += imgDelta.x
            newRect.size.height -= imgDelta.y
            newRect = applyAspectConstraint(newRect, anchorCorner: .bottomLeft, original: dragStartCropRect)
            newRect = clampRect(newRect, to: imageBounds, preserveSize: false)

        case .bottomLeft:
            newRect.origin.x += imgDelta.x
            newRect.size.width  -= imgDelta.x
            newRect.size.height += imgDelta.y
            newRect = applyAspectConstraint(newRect, anchorCorner: .topRight, original: dragStartCropRect)
            newRect = clampRect(newRect, to: imageBounds, preserveSize: false)

        case .bottomRight:
            newRect.size.width  += imgDelta.x
            newRect.size.height += imgDelta.y
            newRect = applyAspectConstraint(newRect, anchorCorner: .topLeft, original: dragStartCropRect)
            newRect = clampRect(newRect, to: imageBounds, preserveSize: false)

        case .topCenter:
            newRect.origin.y += imgDelta.y
            newRect.size.height -= imgDelta.y
            newRect = clampRect(newRect, to: imageBounds, preserveSize: false)

        case .bottomCenter:
            newRect.size.height += imgDelta.y
            newRect = clampRect(newRect, to: imageBounds, preserveSize: false)

        case .leftCenter:
            newRect.origin.x += imgDelta.x
            newRect.size.width -= imgDelta.x
            newRect = clampRect(newRect, to: imageBounds, preserveSize: false)

        case .rightCenter:
            newRect.size.width += imgDelta.x
            newRect = clampRect(newRect, to: imageBounds, preserveSize: false)
        }

        newRect.size.width  = max(newRect.size.width,  minCropSize)
        newRect.size.height = max(newRect.size.height, minCropSize)

        cropRect = newRect
    }

    // MARK: - アスペクト比制約の適用

    private func applyAspectConstraint(_ rect: CGRect, anchorCorner: AnchorCorner, original: CGRect) -> CGRect {
        switch aspectMode {
        case .freeform:
            return rect

        case .square:
            return enforceRatio(rect: rect, ratio: 1.0, anchorCorner: anchorCorner)

        case .original:
            guard rotatedImageSize.height > 0 else { return rect }
            let ratio = rotatedImageSize.width / rotatedImageSize.height
            return enforceRatio(rect: rect, ratio: ratio, anchorCorner: anchorCorner)
        }
    }

    private enum AnchorCorner { case topLeft, topRight, bottomLeft, bottomRight }

    private func enforceRatio(rect: CGRect, ratio: CGFloat, anchorCorner: AnchorCorner) -> CGRect {
        let w = rect.width
        let newH = w / ratio
        var r = rect
        switch anchorCorner {
        case .topLeft:
            r = CGRect(x: rect.minX, y: rect.minY, width: w, height: newH)
        case .topRight:
            r = CGRect(x: rect.minX, y: rect.minY, width: w, height: newH)
        case .bottomLeft:
            r = CGRect(x: rect.minX, y: rect.maxY - newH, width: w, height: newH)
        case .bottomRight:
            r = CGRect(x: rect.minX, y: rect.maxY - newH, width: w, height: newH)
        }
        return r
    }

    private func applyAspectMode(_ mode: CropAspectMode) {
        aspectMode = mode
        switch mode {
        case .freeform:
            break

        case .square:
            let side = min(cropRect.width, cropRect.height)
            let center = CGPoint(x: cropRect.midX, y: cropRect.midY)
            cropRect = CGRect(
                x: center.x - side / 2,
                y: center.y - side / 2,
                width: side, height: side
            )

        case .original:
            guard rotatedImageSize.height > 0 else { break }
            let ratio = rotatedImageSize.width / rotatedImageSize.height
            let newH = cropRect.width / ratio
            let center = CGPoint(x: cropRect.midX, y: cropRect.midY)
            cropRect = CGRect(
                x: center.x - cropRect.width / 2,
                y: center.y - newH / 2,
                width: cropRect.width, height: newH
            )
        }

        let imageBounds = CGRect(origin: .zero, size: image.size)
        cropRect = clampRect(cropRect, to: imageBounds, preserveSize: false)
    }

    // MARK: - ハンドル判定

    private func detectHandle(at point: CGPoint, cropScreenRect: CGRect) -> CropHandle {
        let r = cropScreenRect
        let handles: [(CGPoint, CropHandle)] = [
            (CGPoint(x: r.minX, y: r.minY), .topLeft),
            (CGPoint(x: r.maxX, y: r.minY), .topRight),
            (CGPoint(x: r.minX, y: r.maxY), .bottomLeft),
            (CGPoint(x: r.maxX, y: r.maxY), .bottomRight),
            (CGPoint(x: r.midX, y: r.minY), .topCenter),
            (CGPoint(x: r.midX, y: r.maxY), .bottomCenter),
            (CGPoint(x: r.minX, y: r.midY), .leftCenter),
            (CGPoint(x: r.maxX, y: r.midY), .rightCenter),
        ]

        for (hpt, handle) in handles {
            let dx = point.x - hpt.x
            let dy = point.y - hpt.y
            if sqrt(dx * dx + dy * dy) <= handleHitRadius {
                return handle
            }
        }

        if cropScreenRect.contains(point) {
            return .move
        }

        return .move
    }

    // MARK: - 座標変換ユーティリティ

    private func toScreenRect(_ rect: CGRect, scale: CGFloat, imageOrigin: CGPoint) -> CGRect {
        CGRect(
            x: imageOrigin.x + rect.minX * scale,
            y: imageOrigin.y + rect.minY * scale,
            width:  rect.width  * scale,
            height: rect.height * scale
        )
    }

    private func imageLayoutMetrics(in size: CGSize) -> (scale: CGFloat, origin: CGPoint) {
        let imgSize = rotatedImageSize
        let scaleX = size.width  / imgSize.width
        let scaleY = size.height / imgSize.height
        let scale  = min(scaleX, scaleY)
        let origin = CGPoint(
            x: (size.width  - imgSize.width  * scale) / 2,
            y: (size.height - imgSize.height * scale) / 2
        )
        return (scale, origin)
    }

    private func clampRect(_ rect: CGRect, to bounds: CGRect, preserveSize: Bool) -> CGRect {
        var r = rect
        if preserveSize {
            r.origin.x = max(bounds.minX, min(r.origin.x, bounds.maxX - r.width))
            r.origin.y = max(bounds.minY, min(r.origin.y, bounds.maxY - r.height))
        } else {
            r.origin.x = max(bounds.minX, r.origin.x)
            r.origin.y = max(bounds.minY, r.origin.y)
            if r.maxX > bounds.maxX { r.size.width  = bounds.maxX - r.origin.x }
            if r.maxY > bounds.maxY { r.size.height = bounds.maxY - r.origin.y }
        }
        return r
    }

    // MARK: - クロップ実行

    private func applyCrop() -> UIImage? {
        let src = currentDisplayImage
        guard let cgImage = src.cgImage else { return nil }

        let scaleX = CGFloat(cgImage.width)  / src.size.width
        let scaleY = CGFloat(cgImage.height) / src.size.height

        let pixelRect = CGRect(
            x:      cropRect.origin.x * scaleX,
            y:      cropRect.origin.y * scaleY,
            width:  cropRect.width    * scaleX,
            height: cropRect.height   * scaleY
        )

        guard let cropped = cgImage.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: cropped, scale: src.scale, orientation: .up)
    }

    private func normalizeOrientation(_ src: UIImage) -> UIImage {
        guard src.imageOrientation != .up else { return src }
        let format = UIGraphicsImageRendererFormat()
        format.scale = src.scale
        return UIGraphicsImageRenderer(size: src.size, format: format).image { _ in
            src.draw(in: CGRect(origin: .zero, size: src.size))
        }
    }

    private func applyRotation(to image: UIImage, degrees: Int) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let normalized = ((degrees % 360) + 360) % 360

        let isTransposed = normalized == 90 || normalized == 270
        let origW = CGFloat(cgImage.width)
        let origH = CGFloat(cgImage.height)
        let newW = isTransposed ? origH : origW
        let newH = isTransposed ? origW : origH

        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width:  Int(newW),
            height: Int(newH),
            bitsPerComponent: cgImage.bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: cgImage.bitmapInfo.rawValue
        ) else { return image }

        ctx.translateBy(x: newW / 2, y: newH / 2)
        ctx.rotate(by: CGFloat(normalized) * .pi / 180)
        ctx.translateBy(x: -origW / 2, y: -origH / 2)
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: origW, height: origH))

        guard let rotatedCG = ctx.makeImage() else { return image }
        return UIImage(cgImage: rotatedCG, scale: image.scale, orientation: .up)
    }
}
