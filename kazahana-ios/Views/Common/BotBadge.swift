import SwiftUI

/// Bot account badge displayed next to display names.
/// Uses the Material Symbols Rounded "smart_toy" glyph (U+F06C) from SmartToy.ttf.
struct BotBadge: View {
    var size: CGFloat = 14

    var body: some View {
        Text("\u{F06C}")
            .font(.custom("MaterialSymbolsRounded-Regular", size: size))
            .foregroundStyle(.secondary)
            .accessibilityLabel(String(localized: "bot.label"))
    }
}

/// Returns true if the account with the given DID has self-applied the "bot" label.
/// Both conditions must be met: label value is "bot" AND label source equals the account's own DID.
func isBotAccount(did: String, labels: [ContentLabel]?) -> Bool {
    labels?.contains(where: { $0.val == "bot" && $0.src == did }) ?? false
}

#Preview {
    HStack {
        Text("MyBot")
        BotBadge()
    }
    .padding()
}
