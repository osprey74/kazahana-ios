// View+InteractivePop.swift
// kazahana-ios
// ナビバー非表示時もエッジスワイプで戻れるようにする

import SwiftUI
import UIKit

extension View {
    /// `.toolbar(.hidden, for: .navigationBar)` 使用時に
    /// エッジスワイプによるポップジェスチャーを有効に保つ
    func enableInteractivePop() -> some View {
        self.background(InteractivePopEnabler())
    }
}

/// UIViewController のライフサイクルを使って
/// interactivePopGestureRecognizer を有効にする軽量ヘルパー
private struct InteractivePopEnabler: UIViewControllerRepresentable {

    func makeUIViewController(context: Context) -> Wrapper {
        Wrapper()
    }

    func updateUIViewController(_ uiViewController: Wrapper, context: Context) {}

    final class Wrapper: UIViewController {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
        }
    }
}
