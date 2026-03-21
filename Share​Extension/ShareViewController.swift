// ShareViewController.swift
// Share​Extension
// 共有コンテンツのタイトルと URL を App Groups 経由で kazahana アプリへ渡す

import UIKit
import UniformTypeIdentifiers

@objc(ShareViewController)
class ShareViewController: UIViewController {

    private static let suiteName   = "group.com.osprey74.kazahana-ios"
    private static let pendingKey  = "shareExtension.pendingText"

    override func viewDidLoad() {
        super.viewDidLoad()
        extractContent { [weak self] text in
            guard let self else { return }
            self.savePendingText(text)
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    // MARK: - コンテンツ抽出

    private func extractContent(completion: @escaping (String) -> Void) {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem else {
            completion("")
            return
        }

        let attachments = extensionItem.attachments ?? []

        // URL を最優先で探す
        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, _ in
                    guard let self else { return }
                    let urlString = (item as? URL)?.absoluteString ?? ""
                    let title = extensionItem.attributedTitle?.string
                        ?? extensionItem.attributedContentText?.string
                        ?? ""
                    let text = self.buildText(title: title, url: urlString)
                    DispatchQueue.main.async { completion(text) }
                }
                return
            }
        }

        // URL がなければプレーンテキストを探す
        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                    let text = (item as? String) ?? ""
                    DispatchQueue.main.async { completion(text) }
                }
                return
            }
        }

        completion("")
    }

    private func buildText(title: String, url: String) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return u }
        if u.isEmpty { return t }
        return "\(t)\n\(u)"
    }

    // MARK: - App Groups への保存

    private func savePendingText(_ text: String) {
        guard !text.isEmpty,
              let defaults = UserDefaults(suiteName: Self.suiteName) else { return }
        defaults.set(text, forKey: Self.pendingKey)
        defaults.synchronize()
    }
}
