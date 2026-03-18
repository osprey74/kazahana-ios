import Foundation

/// String を Identifiable/Hashable として navigationDestination(item:) に渡すためのラッパー
struct IdentifiableString: Identifiable, Hashable {
    let value: String
    var id: String { value }

    init(_ value: String) {
        self.value = value
    }
}
