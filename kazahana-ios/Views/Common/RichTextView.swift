// RichTextView.swift
// kazahana-ios
// リンク付きリッチテキストの表示ビュー（iOS: SwiftUI Text / Mac Catalyst: UITextView）

import SwiftUI
import UIKit

/// RichTextParser が生成した AttributedString（リンク付き）を表示する。
///
/// macOS 27 の Mac Catalyst では、.link を含む SwiftUI Text をノッチ付きホイールのマウスで
/// スクロールすると UIScrollEvent.m:618 のアサーションが繰り返され、
/// 「sendEvent: nesting level exceeded」でアプリが終了する（OS 側の不具合）。
/// UITextView で表示すると発生しないため、Catalyst のみ UITextView を使う。
struct RichTextView: View {
    let text: AttributedString
    var font: Font = AppSettings.shared.fontSize.bodyFont
    var uiFont: UIFont = AppSettings.shared.fontSize.uiFont
    /// リンク以外の文字色（Catalyst のみ使用。iOS は foregroundStyle を継承）
    var textColor: UIColor = .label
    var lineLimit: Int? = nil

    var body: some View {
        #if targetEnvironment(macCatalyst)
        CatalystRichTextView(text: text, font: uiFont, textColor: textColor, lineLimit: lineLimit)
        #else
        Text(text)
            .font(font)
            .lineLimit(lineLimit)
        #endif
    }
}

#if targetEnvironment(macCatalyst)
private struct CatalystRichTextView: UIViewRepresentable {
    let text: AttributedString
    let font: UIFont
    let textColor: UIColor
    let lineLimit: Int?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> LinkOnlyTextView {
        let textView = LinkOnlyTextView()
        textView.isEditable = false
        textView.isSelectable = true   // リンクのクリックに必要
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byTruncatingTail
        textView.linkTextAttributes = [:]   // リンク色は AttributedString 側の指定に従う
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.delegate = context.coordinator
        return textView
    }

    func updateUIView(_ textView: LinkOnlyTextView, context: Context) {
        context.coordinator.openURL = context.environment.openURL
        textView.textContainer.maximumNumberOfLines = lineLimit ?? 0
        textView.attributedText = makeAttributedString()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: LinkOnlyTextView, context: Context) -> CGSize? {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        let fitted = uiView.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        return CGSize(width: min(ceil(fitted.width), maxWidth), height: ceil(fitted.height))
    }

    /// SwiftUI の属性（foregroundColor / link / underlineStyle）を UIKit の属性に変換する
    private func makeAttributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in text.runs {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: run.foregroundColor.map { UIColor($0) } ?? textColor
            ]
            if let link = run.link {
                attributes[.link] = link
            }
            if run.underlineStyle != nil {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            result.append(NSAttributedString(string: String(text[run.range].characters), attributes: attributes))
        }
        return result
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var openURL: OpenURLAction?

        /// リンクのクリックを SwiftUI の openURL に渡す（各画面の kazahana:// ハンドラーを効かせるため）
        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            guard case .link(let url) = textItem.content, let openURL else { return defaultAction }
            return UIAction { _ in openURL(url) }
        }
    }
}

/// リンク上のクリックだけを受け取り、それ以外は背後の SwiftUI（投稿タップ等）に素通しする UITextView
private final class LinkOnlyTextView: UITextView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event), attributedText.length > 0 else { return false }
        let location = CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top)
        let index = layoutManager.characterIndex(
            for: location, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil
        )
        guard index < attributedText.length else { return false }
        // 行末より右側の余白は characterIndex が最後の文字を返すため、文字の矩形内かも確認する
        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        guard rect.contains(location) else { return false }
        return attributedText.attribute(.link, at: index, effectiveRange: nil) != nil
    }
}
#endif
