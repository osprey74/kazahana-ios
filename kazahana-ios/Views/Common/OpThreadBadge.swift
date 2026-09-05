import SwiftUI

/// OP スレッド番号付けバッジ（例: 2/3）。
/// 同一著者による連続スレッド内の位置を表示する。
struct OpThreadBadge: View {
    let index: Int
    let count: Int
    var size: CGFloat = 11

    var body: some View {
        Text("\(index)/\(count)")
            .font(.system(size: size, weight: .semibold).monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}

#Preview {
    HStack {
        Text("Author Name")
        OpThreadBadge(index: 2, count: 3)
    }
    .padding()
}
