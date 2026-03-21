// ShareViewController.swift
// Share​Extension
// 共有コンテンツのタイトルと URL を kazahana アプリへ渡して起動する

import UIKit
import UniformTypeIdentifiers

@objc(ShareViewController)
class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        extractContent { [weak self] text in
            guard let self else { return }
            self.launchKazahana(with: text)
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

    // MARK: - kazahana 起動

    private func launchKazahana(with text: String) {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "kazahana://compose?text=\(encoded)") else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        // Share Extension から他アプリを URL スキームで起動する
        // responder chain を辿って UIApplication を取得し open(_:) を呼ぶ
        openURL(url)
        extensionContext?.completeRequest(returningItems: nil)
    }

    // UIResponder の openURL を辿るヘルパー
    // Swift では UIApplication.open を直接呼べないため @objc セレクタ経由で実行
    @objc private func openURL(_ url: URL) {
        var responder: UIResponder? = self
        while let r = responder {
            if r.responds(to: #selector(UIApplication.open(_:options:completionHandler:))) {
                r.perform(
                    #selector(UIApplication.open(_:options:completionHandler:)),
                    with: url,
                    with: [String: Any]()
                )
                return
            }
            responder = r.next
        }
    }
}
