// EvacuationBannerView.swift
// kazahana-ios
// 避難誘導バナー（画面下部に常駐。レベルに応じた色で警報情報を表示）

import SwiftUI

struct EvacuationBannerView: View {
    let highestLevel: AlertLevel
    let alertCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText)
                        .font(.subheadline.weight(.semibold))
                    if alertCount > 1 {
                        Text(String(localized: "evacuation.bannerMultiple \(alertCount)"))
                            .font(.caption)
                            .opacity(0.9)
                    }
                }

                Spacer()

                Text(String(localized: "evacuation.bannerAction"))
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(bannerColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: bannerColor.opacity(0.3), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Private

    private var iconName: String {
        switch highestLevel {
        case .level3: return "exclamationmark.triangle"
        case .level4: return "exclamationmark.triangle.fill"
        case .level5: return "exclamationmark.octagon.fill"
        }
    }

    private var titleText: String {
        switch highestLevel {
        case .level3: return String(localized: "evacuation.bannerTitle.level3")
        case .level4: return String(localized: "evacuation.bannerTitle.level4")
        case .level5: return String(localized: "evacuation.bannerTitle.level5")
        }
    }

    private var bannerColor: Color {
        Color(hex: highestLevel.bannerColorHex)
    }
}
