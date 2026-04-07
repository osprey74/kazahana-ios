// WatermarkService.swift
// kazahana-ios
// ウォーターマーク合成ロジック（Desktop 実装に準拠）

import UIKit

struct WatermarkService {

    // MARK: - テキスト解決（スマート改行）

    /// 画像幅に収まれば1行、はみ出す場合のみ2行に分割する。
    /// - Parameters:
    ///   - maxWidth: 利用可能な最大テキスト幅（margin・padding を差し引いた値）
    ///   - font: 使用するフォント（幅計算に必要）
    static func resolveLines(settings: WatermarkSettings, handle: String,
                             maxWidth: CGFloat, font: UIFont) -> [String] {
        let h = "© @\(handle)"

        if settings.preset == .custom {
            let lines = settings.customText.components(separatedBy: "\n").filter { !$0.isEmpty }
            return lines.isEmpty ? [h] : lines
        }

        let labelMap: [WatermarkPreset: String] = [
            .copyright: "無断転載禁止",
            .ai_ja:     "AI学習・転載禁止",
            .ai_en:     "No AI Training",
            .ai_both:   "No AI Training / 無断転載禁止",
            .photo:     "撮影・編集",
        ]
        guard let label = labelMap[settings.preset] else { return [h] }

        // まず1行版のテキスト幅を測定し、収まれば1行で描画
        let single = "\(h)\u{3000}\(label)"
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let singleWidth = (single as NSString).size(withAttributes: attrs).width
        return singleWidth <= maxWidth ? [single] : [h, label]
    }

    // MARK: - カラー変換

    /// "#RRGGBB" 形式の HEX 文字列を UIColor に変換する。
    static func hexToUIColor(_ hex: String, alpha: CGFloat) -> UIColor {
        var h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let n = UInt64(h, radix: 16) else {
            return UIColor.white.withAlphaComponent(alpha)
        }
        let r = CGFloat((n >> 16) & 0xFF) / 255.0
        let g = CGFloat((n >> 8) & 0xFF) / 255.0
        let b = CGFloat(n & 0xFF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: alpha)
    }

    // MARK: - 合成

    /// 画像にウォーターマークを合成して返す。
    /// UIGraphicsImageRenderer はメインスレッド必須のため @MainActor を付与。
    @MainActor
    static func apply(to image: UIImage, settings: WatermarkSettings, handle: String) -> UIImage {
        let size = image.size

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.image { _ in
            image.draw(at: .zero)

            let baseFontSize = max(settings.fontSize, Double(size.width) * 0.022)
            let font = UIFont.boldSystemFont(ofSize: baseFontSize)
            let textAlpha = settings.opacity / 100.0
            let bgAlpha   = textAlpha * 0.6
            let lineGap   = baseFontSize * 0.3
            let padX = baseFontSize * 1.0
            let padY = baseFontSize * 0.7
            let margin = size.width * 0.015
            let maxAvailableWidth = size.width - margin * 2 - padX * 2

            let lines = resolveLines(settings: settings, handle: handle,
                                     maxWidth: maxAvailableWidth, font: font)

            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: hexToUIColor(settings.textColor, alpha: textAlpha)
            ]
            let maxLineWidth = lines.map { ($0 as NSString).size(withAttributes: attrs).width }.max() ?? 0
            let boxW = maxLineWidth + padX * 2
            let boxH = baseFontSize * CGFloat(lines.count) + lineGap * CGFloat(lines.count - 1) + padY * 2

            let origin = calcOrigin(pos: settings.position, imgSize: size,
                                    boxSize: CGSize(width: boxW, height: boxH), margin: margin)
            let boxRect = CGRect(origin: origin, size: CGSize(width: boxW, height: boxH))

            // 半透明背景
            let bgPath = UIBezierPath(roundedRect: boxRect, cornerRadius: 4)
            UIColor.black.withAlphaComponent(bgAlpha).setFill()
            bgPath.fill()

            // 各行を描画
            for (i, line) in lines.enumerated() {
                let ly = origin.y + padY + CGFloat(i) * (baseFontSize + lineGap)
                (line as NSString).draw(at: CGPoint(x: origin.x + padX, y: ly), withAttributes: attrs)
            }
        }
    }

    // MARK: - Private

    private static func calcOrigin(pos: WatermarkPosition, imgSize: CGSize,
                                   boxSize: CGSize, margin: CGFloat) -> CGPoint {
        let x: CGFloat
        let y: CGFloat
        switch pos {
        case .tl: x = margin;                                    y = margin
        case .tc: x = (imgSize.width - boxSize.width) / 2;      y = margin
        case .tr: x = imgSize.width - boxSize.width - margin;   y = margin
        case .bl: x = margin;                                    y = imgSize.height - boxSize.height - margin
        case .bc: x = (imgSize.width - boxSize.width) / 2;      y = imgSize.height - boxSize.height - margin
        case .br: x = imgSize.width - boxSize.width - margin;   y = imgSize.height - boxSize.height - margin
        }
        return CGPoint(x: x, y: y)
    }
}
