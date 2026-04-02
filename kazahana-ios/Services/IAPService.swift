// IAPService.swift
// kazahana-ios
// アプリ内課金（サポーターバッジ）管理サービス（StoreKit 2）

import StoreKit
import Foundation

@Observable
final class IAPService {

    // MARK: - Constants

    static let productID = "com.osprey74.kazahana.supporter_badge_30d"
    static let badgeDuration: TimeInterval = 30 * 24 * 60 * 60  // 30日

    // MARK: - State

    var product: Product?
    var isLoadingProducts = true   // true on init so spinner shows before first fetch
    var isPurchasing = false
    var isRestoring = false
    var purchaseError: String?

    // MARK: - Singleton

    static let shared = IAPService()

    // MARK: - Product Fetch

    /// App Store から商品情報を取得する
    func fetchProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let products = try await Product.products(for: [IAPService.productID])
            product = products.first
        } catch {
            // 取得失敗は静かに無視（UI でハンドル）
        }
    }

    // MARK: - Purchase

    /// サポーターバッジを購入する。成功した場合は AppSettings の有効期限を更新する。
    @discardableResult
    func purchase(settings: AppSettings) async throws -> Bool {
        guard let product = product else {
            throw IAPError.productNotFound
        }
        isPurchasing = true
        defer { isPurchasing = false }
        purchaseError = nil

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updateExpiryDate(transaction: transaction, settings: settings)
            await transaction.finish()
            return true

        case .userCancelled:
            return false

        case .pending:
            return false

        @unknown default:
            return false
        }
    }

    // MARK: - Restore

    /// 過去の購入をリストアし、有効期限を再計算する
    func restorePurchases(settings: AppSettings) async {
        isRestoring = true
        defer { isRestoring = false }
        purchaseError = nil

        var latestDate: Date? = nil

        for await result in Transaction.all {
            if case .verified(let transaction) = result,
               transaction.productID == IAPService.productID,
               transaction.revocationDate == nil {
                let expiry = transaction.purchaseDate.addingTimeInterval(IAPService.badgeDuration)
                if latestDate == nil || expiry > latestDate! {
                    latestDate = expiry
                }
            }
        }

        if let expiry = latestDate {
            settings.supporterBadgeExpiryDate = expiry
        }
    }

    // MARK: - Transaction Listener

    /// App Store からのトランザクション更新を監視するタスクを開始する
    @discardableResult
    func listenForTransactions(settings: AppSettings) -> Task<Void, Never> {
        Task(priority: .background) {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result,
                   transaction.productID == IAPService.productID {
                    await self.updateExpiryDate(transaction: transaction, settings: settings)
                    await transaction.finish()
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw IAPError.verificationFailed
        case .verified(let value):
            return value
        }
    }

    private func updateExpiryDate(transaction: Transaction, settings: AppSettings) async {
        guard transaction.revocationDate == nil else {
            // 返金済みの場合は期限を無効化
            if let current = settings.supporterBadgeExpiryDate,
               current <= transaction.purchaseDate.addingTimeInterval(IAPService.badgeDuration) {
                settings.supporterBadgeExpiryDate = nil
            }
            return
        }
        let newExpiry = transaction.purchaseDate.addingTimeInterval(IAPService.badgeDuration)
        if settings.supporterBadgeExpiryDate == nil || newExpiry > settings.supporterBadgeExpiryDate! {
            settings.supporterBadgeExpiryDate = newExpiry
        }
    }
}

// MARK: - IAP Error

enum IAPError: LocalizedError {
    case productNotFound
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return String(localized: "iap.error.productNotFound")
        case .verificationFailed:
            return String(localized: "iap.error.verificationFailed")
        }
    }
}
