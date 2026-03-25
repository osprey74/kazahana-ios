import Foundation

/// String を Identifiable/Hashable として navigationDestination(item:) に渡すためのラッパー
struct IdentifiableString: Identifiable, Hashable {
    let value: String
    var id: String { value }

    init(_ value: String) {
        self.value = value
    }

    init(value: String) {
        self.value = value
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// kazahana:// ディープリンク受信通知（userInfo["url"] に URL が入る）
    static let kazahanaDeepLink = Notification.Name("kazahanaDeepLink")
    /// ホームタブの再タップ通知 — TimelineView がこれを受信してスクロール先頭 + 再読み込みする
    static let timelineScrollToTop = Notification.Name("timelineScrollToTop")
    /// ハッシュタグ検索通知 — userInfo["tag"] にタグ文字列（# なし）が入る
    static let searchHashtag = Notification.Name("searchHashtag")
}
