// ModerationService.swift
// kazahana-ios
// コンテンツモデレーション判定ロジック

import Foundation

// MARK: - モデレーション判定結果

enum ModerationDecision: Equatable {
    case none       // ラベルなし or 無視（通常表示）
    case inform     // 情報表示のみ（将来拡張用）
    case mediaBlur  // メディアのみブラー（本文は表示）
    case blur       // 投稿全体ブラー
    case filter     // 非表示（タイムラインから除外）
}

struct ModerationResult: Equatable {
    let decision: ModerationDecision
    /// ブラー/警告時に表示するラベル名
    let message: String?

    static let none = ModerationResult(decision: .none, message: nil)
}

// MARK: - ModerationService

struct ModerationService {

    private let settings: AppSettings

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    // MARK: - 投稿のモデレーション判定

    /// 投稿ラベル＋著者ラベルを評価して最も厳しい判定を返す
    func moderatePost(_ post: PostView) -> ModerationResult {
        let postLabels = post.labels ?? []
        let authorLabels = post.author.labels ?? []
        return evaluateLabels(postLabels + authorLabels)
    }

    /// ProfileViewBasic のラベルを評価
    func moderateAuthor(labels: [ContentLabel]?) -> ModerationResult {
        evaluateLabels(labels ?? [])
    }

    // MARK: - ラベル評価

    private func evaluateLabels(_ labels: [ContentLabel]) -> ModerationResult {
        guard !labels.isEmpty else { return .none }

        var worstDecision: ModerationDecision = .none
        var message: String? = nil

        for label in labels {
            // neg == true は打ち消しラベルのため無視
            if label.neg == true { continue }

            let result = evaluateSingleLabel(label.val)
            if result.decision.severity > worstDecision.severity {
                worstDecision = result.decision
                message = result.message
            }
        }

        return ModerationResult(decision: worstDecision, message: message)
    }

    private func evaluateSingleLabel(_ val: String) -> ModerationResult {
        switch val {
        // システムラベル（ユーザー設定に関わらず固定）
        case "!hide":
            return ModerationResult(decision: .filter, message: nil)
        case "!warn":
            return ModerationResult(decision: .blur, message: "コンテンツ警告")
        case "!no-unauthenticated":
            // 認証済みユーザーには影響なし
            return .none

        // 成人向けコンテンツ
        case "porn", "sexual", "nudity":
            return evaluateAdultLabel(val)

        // グラフィックコンテンツ（成人向けトグルとは独立）
        case "graphic-media", "gore":
            return evaluateGraphicLabel(val)

        default:
            return .none
        }
    }

    private func evaluateAdultLabel(_ val: String) -> ModerationResult {
        // 成人向けコンテンツ無効なら問答無用で非表示
        guard settings.adultContentEnabled else {
            return ModerationResult(decision: .filter, message: nil)
        }
        let behavior = settings.labelPreferences[val] ?? .warn
        return applyBehavior(behavior, val: val, isMediaOnly: true)
    }

    private func evaluateGraphicLabel(_ val: String) -> ModerationResult {
        let behavior = settings.labelPreferences[val] ?? .warn
        return applyBehavior(behavior, val: val, isMediaOnly: true)
    }

    private func applyBehavior(
        _ behavior: AppSettings.ModerationBehavior,
        val: String,
        isMediaOnly: Bool
    ) -> ModerationResult {
        switch behavior {
        case .hide:
            return ModerationResult(decision: .filter, message: nil)
        case .warn:
            let decision: ModerationDecision = isMediaOnly ? .mediaBlur : .blur
            return ModerationResult(decision: decision, message: labelDisplayName(val))
        case .ignore:
            return .none
        }
    }

    private func labelDisplayName(_ val: String) -> String {
        switch val {
        case "porn":         return "ポルノグラフィ"
        case "sexual":       return "性的コンテンツ"
        case "graphic-media":return "グラフィックメディア"
        case "nudity":       return "ヌード"
        case "gore":         return "暴力的コンテンツ"
        default:             return "センシティブなコンテンツ"
        }
    }
}

// MARK: - severity 比較用

private extension ModerationDecision {
    var severity: Int {
        switch self {
        case .none:      return 0
        case .inform:    return 1
        case .mediaBlur: return 2
        case .blur:      return 3
        case .filter:    return 4
        }
    }
}
