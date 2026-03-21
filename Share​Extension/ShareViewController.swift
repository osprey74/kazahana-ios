// ShareViewController.swift
// Share​Extension
// 共有コンテンツのタイトルと URL を kazahana アプリへ渡して起動する

import UIKit
import UniformTypeIdentifiers
import Social

@objc(ShareViewController)
class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        extractContent { [weak self] text in
            guard let self else { return }
            self.openKazahana(with: text)
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
                    let url = (item as? URL)?.absoluteString ?? ""
                    // extensionItem のタイトルも取得
                    let title = extensionItem.attributedTitle?.string
                        ?? extensionItem.attributedContentText?.string
                        ?? ""
                    let text = self.buildText(title: title, url: url)
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
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL   = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            return trimmedURL
        }
        if trimmedURL.isEmpty {
            return trimmedTitle
        }
        return "\(trimmedTitle)\n\(trimmedURL)"
    }

    // MARK: - kazahana 起動

    private func openKazahana(with text: String) {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "kazahana://compose?text=\(encoded)") else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        // extensionContext?.open は iOS 17 以降でも Share Extension で使用可能
        extensionContext?.open(url) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
