// ShareViewController.swift
// Share​Extension
// 共有シートのエントリポイント — SwiftUI の ShareComposeView をホストする

import UIKit
import SwiftUI

@objc(ShareViewController)
class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let session = SessionStore().load()
        let composeView = ShareComposeView(
            extensionContext: extensionContext,
            session: session
        )
        let hosting = UIHostingController(rootView: composeView)
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)
    }
}
