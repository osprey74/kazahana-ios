// ShareViewController.swift
// Share​Extension
// Share Extension のエントリポイント。SwiftUI ビューをホストする。

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
        view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hosting.didMove(toParent: self)
    }
}
