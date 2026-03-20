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
}
