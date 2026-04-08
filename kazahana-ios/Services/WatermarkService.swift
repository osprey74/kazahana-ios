// WatermarkService.swift
// kazahana-ios
// ウォーターマーク合成ロジック（Desktop 実装に準拠）

import UIKit

struct WatermarkService {

    // MARK: - テキスト解決（スマート改行）

    /// 画像幅に収まれば1行、はみ出す場合のみ2行に分割する。
    static func resolveLines(settings: WatermarkSettings, handle: String,
                             maxWidth: CGFloat, font: UIFont) -> [String] {
        let h = "© @\(handle)"

        if settings.preset == .custom {
            let lines = settings.customText.components(separatedBy: "\n").filter { !$0.isEmpty }
            return lines.isEmpty ? [h] : lines
        }

        let lang = AppSettings.shared.postLanguageSetting.rawValue
        let label: String
        switch settings.preset {
        case .copyright: label = WatermarkService.wmCopyright(lang: lang)
        case .ai_ja:     label = WatermarkService.wmAiNoTraining(lang: lang)
        case .ai_en:     label = "No AI Training"
        case .ai_both:   label = "No AI Training / \(WatermarkService.wmCopyright(lang: lang))"
        case .photo:     label = WatermarkService.wmPhoto(lang: lang)
        default:         label = ""
        }
        guard !label.isEmpty else { return [h] }

        let single = "\(h)\u{3000}\(label)"
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let singleWidth = (single as NSString).size(withAttributes: attrs).width
        return singleWidth <= maxWidth ? [single] : [h, label]
    }

    // MARK: - 多言語焼き込み文言

    /// 「無断転載禁止」をアプリ設定言語で返す
    private static func wmCopyright(lang: String) -> String {
        switch lang {
        case "ja":    return "無断転載禁止"
        case "zh-TW": return "禁止轉載"
        case "zh-CN": return "禁止转载"
        case "ko":    return "무단전재 금지"
        case "pt":    return "Sem redistribuição"
        case "de":    return "Nicht verbreiten"
        case "fr":    return "Non redistribuable"
        case "es":    return "No redistribuir"
        case "ru":    return "Без распростр."
        case "id":    return "Dilarang disebarkan"
        default:      return "No Redistribution"
        }
    }

    /// 「AI学習・転載禁止」をアプリ設定言語で返す
    private static func wmAiNoTraining(lang: String) -> String {
        switch lang {
        case "ja":    return "AI学習・転載禁止"
        case "zh-TW": return "禁止AI學習・轉載"
        case "zh-CN": return "禁止AI学习・转载"
        case "ko":    return "AI 학습·전재 금지"
        case "pt":    return "Sem IA/redistrib."
        case "de":    return "Kein KI/Verbreiten"
        case "fr":    return "Sans IA/redistrib."
        case "es":    return "Sin IA/redistrib."
        case "ru":    return "Без ИИ/распростр."
        case "id":    return "Tanpa AI/Sebarkan"
        default:      return "No AI/Redistribution"
        }
    }

    /// 「撮影・編集」をアプリ設定言語で返す
    private static func wmPhoto(lang: String) -> String {
        switch lang {
        case "ja":    return "撮影・編集"
        case "zh-TW": return "拍攝・編輯"
        case "zh-CN": return "拍摄・编辑"
        case "ko":    return "촬영・편집"
        case "pt":    return "Foto & Edição"
        case "de":    return "Foto & Bearb."
        case "fr":    return "Photo & Édit."
        case "es":    return "Foto y edic."
        case "ru":    return "Фото и ред."
        case "id":    return "Foto & Edit"
        default:      return "Photo & Edit"
        }
    }

    // MARK: - カラー変換

    static func hexToUIColor(_ hex: String, alpha: CGFloat) -> UIColor {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let n = UInt64(h, radix: 16) else {
            return UIColor.white.withAlphaComponent(alpha)
        }
        let r = CGFloat((n >> 16) & 0xFF) / 255.0
        let g = CGFloat((n >> 8) & 0xFF) / 255.0
        let b = CGFloat(n & 0xFF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: alpha)
    }

    // MARK: - 合成エントリポイント

    @MainActor
    static func apply(to image: UIImage, settings: WatermarkSettings, handle: String) -> UIImage {
        let size = image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.image { rendererCtx in
            image.draw(at: .zero)

            let baseFontSize = max(settings.fontSize, Double(size.width) * 0.022)
            let font = UIFont.boldSystemFont(ofSize: baseFontSize)
            let textAlpha = settings.opacity / 100.0
            let bgAlpha   = textAlpha * 0.6
            let lineGap   = baseFontSize * 0.3
            let padX = baseFontSize * 1.0
            let padY = baseFontSize * 0.7
            let margin = size.width * 0.015
            let maxAvailableWidth = max(0, size.width - margin * 2 - padX * 2)

            let lines = resolveLines(settings: settings, handle: handle,
                                     maxWidth: maxAvailableWidth, font: font)

            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: hexToUIColor(settings.textColor, alpha: textAlpha)
            ]
            let maxLineWidth = lines.map { ($0 as NSString).size(withAttributes: attrs).width }.max() ?? 0
            let boxW = maxLineWidth + padX * 2
            let boxH = baseFontSize * CGFloat(lines.count) + lineGap * CGFloat(lines.count - 1) + padY * 2
            let boxSize = CGSize(width: boxW, height: boxH)

            switch settings.position {
            case .tile:
                drawTiled(cgContext: rendererCtx.cgContext,
                          imgSize: size, lines: lines, attrs: attrs,
                          boxW: boxW, boxH: boxH, padX: padX, padY: padY,
                          lineGap: lineGap, baseFontSize: baseFontSize, bgAlpha: bgAlpha)
            case .random:
                let origin = calcRandomOrigin(imgSize: size, boxSize: boxSize, margin: margin)
                drawBox(at: origin, lines: lines, attrs: attrs,
                        boxW: boxW, boxH: boxH, padX: padX, padY: padY,
                        lineGap: lineGap, baseFontSize: baseFontSize, bgAlpha: bgAlpha)
            default:
                let origin = calcOrigin(pos: settings.position, imgSize: size,
                                        boxSize: boxSize, margin: margin)
                drawBox(at: origin, lines: lines, attrs: attrs,
                        boxW: boxW, boxH: boxH, padX: padX, padY: padY,
                        lineGap: lineGap, baseFontSize: baseFontSize, bgAlpha: bgAlpha)
            }
        }
    }

    // MARK: - 単体ボックス描画

    private static func drawBox(at origin: CGPoint, lines: [String],
                                 attrs: [NSAttributedString.Key: Any],
                                 boxW: CGFloat, boxH: CGFloat, padX: CGFloat, padY: CGFloat,
                                 lineGap: CGFloat, baseFontSize: CGFloat, bgAlpha: CGFloat) {
        let boxRect = CGRect(origin: origin, size: CGSize(width: boxW, height: boxH))
        let bgPath = UIBezierPath(roundedRect: boxRect, cornerRadius: 4)
        UIColor.black.withAlphaComponent(bgAlpha).setFill()
        bgPath.fill()

        for (i, line) in lines.enumerated() {
            let ly = origin.y + padY + CGFloat(i) * (baseFontSize + lineGap)
            (line as NSString).draw(at: CGPoint(x: origin.x + padX, y: ly), withAttributes: attrs)
        }
    }

    // MARK: - ランダム配置

    private static func calcRandomOrigin(imgSize: CGSize, boxSize: CGSize, margin: CGFloat) -> CGPoint {
        // x = margin + random × (imgWidth - boxW - margin×2)
        // y = margin + random × (imgHeight - boxH - margin×2)
        let availableX = imgSize.width - boxSize.width - margin * 2
        let availableY = imgSize.height - boxSize.height - margin * 2
        let x = margin + (availableX > 0 ? CGFloat.random(in: 0...availableX) : 0)
        let y = margin + (availableY > 0 ? CGFloat.random(in: 0...availableY) : 0)
        return CGPoint(x: x, y: y)
    }

    // MARK: - タイリング配置

    /// 被覆率 ~20% の市松模様で画像全体にウォーターマークを繰り返し配置。
    /// 各タイルは -30° 回転。中央アンカー方式で中央タイルを常に画像内に収める。
    private static func drawTiled(cgContext: CGContext, imgSize: CGSize,
                                   lines: [String], attrs: [NSAttributedString.Key: Any],
                                   boxW: CGFloat, boxH: CGFloat, padX: CGFloat, padY: CGFloat,
                                   lineGap: CGFloat, baseFontSize: CGFloat, bgAlpha: CGFloat) {
        // 被覆率 20% になる間隔: spacing = sqrt(boxW × boxH / 0.2)
        let spacing = sqrt(boxW * boxH / 0.2)
        let angle = CGFloat(-30) * .pi / 180

        let centerX = imgSize.width / 2
        let centerY = imgSize.height / 2

        // 画像全体をカバーするためのタイル数（対角線 ÷ 間隔 + 余裕）
        let diagonal = sqrt(imgSize.width * imgSize.width + imgSize.height * imgSize.height)
        let steps = Int(ceil(diagonal / spacing)) + 1

        for row in -steps...steps {
            for col in -steps...steps {
                // 中央アンカー: グリッド起点を画像中央に設定
                var tileX = centerX + CGFloat(col) * spacing
                let tileY = centerY + CGFloat(row) * spacing

                // 奇数行は半間隔ずらして市松配置
                if abs(row) % 2 == 1 {
                    tileX += spacing / 2
                }

                cgContext.saveGState()
                // タイル中心へ移動 → -30° 回転 → タイル左上へオフセット
                cgContext.translateBy(x: tileX, y: tileY)
                cgContext.rotate(by: angle)
                cgContext.translateBy(x: -boxW / 2, y: -boxH / 2)

                // 半透明背景
                let bgPath = UIBezierPath(
                    roundedRect: CGRect(x: 0, y: 0, width: boxW, height: boxH),
                    cornerRadius: 4
                )
                UIColor.black.withAlphaComponent(bgAlpha).setFill()
                bgPath.fill()

                // テキスト各行を描画
                for (i, line) in lines.enumerated() {
                    let ly = padY + CGFloat(i) * (baseFontSize + lineGap)
                    (line as NSString).draw(at: CGPoint(x: padX, y: ly), withAttributes: attrs)
                }

                cgContext.restoreGState()
            }
        }
    }

    // MARK: - 固定6方向の座標計算

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
        default:  x = imgSize.width - boxSize.width - margin;   y = imgSize.height - boxSize.height - margin  // br
        }
        return CGPoint(x: x, y: y)
    }
}
