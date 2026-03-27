// SessionStore.swift
// kazahana-ios
// Keychain を使ったセッション情報の永続化

import Foundation
import Security

/// セッション情報を Keychain に保存・取得・削除する
final class SessionStore {

    private enum Keys {
        static let service = "com.osprey74.kazahana-ios"
        static let account = "session"
        /// Share Extension と Keychain を共有するための Access Group
        /// Team ID (9L6A9KDH5P) + Bundle ID (com.osprey74.kazahana-ios)
        static let accessGroup = "9L6A9KDH5P.com.osprey74.kazahana-ios"
    }

    init() {
        migrateIfNeeded()
    }

    // MARK: - 保存

    func save(_ session: Session) throws {
        let data = try JSONEncoder().encode(session)

        // 既存エントリを削除してから保存（update でも可だが、削除→追加が確実）
        delete()

        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      Keys.service,
            kSecAttrAccount as String:      Keys.account,
            kSecAttrAccessGroup as String:  Keys.accessGroup,
            kSecValueData as String:        data,
            kSecAttrAccessible as String:   kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SessionStoreError.saveFailed(status)
        }
    }

    // MARK: - 取得

    func load() -> Session? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      Keys.service,
            kSecAttrAccount as String:      Keys.account,
            kSecAttrAccessGroup as String:  Keys.accessGroup,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let session = try? JSONDecoder().decode(Session.self, from: data) else {
            return nil
        }
        return session
    }

    // MARK: - 削除

    @discardableResult
    func delete() -> Bool {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      Keys.service,
            kSecAttrAccount as String:      Keys.account,
            kSecAttrAccessGroup as String:  Keys.accessGroup
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - 移行（accessGroup なし → あり）

    /// accessGroup を追加する前の旧形式から新形式へ一回限り移行する
    private func migrateIfNeeded() {
        // 新形式で既に存在するなら移行不要
        if load() != nil { return }

        // 旧形式（accessGroup なし）で試みる
        let oldQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Keys.service,
            kSecAttrAccount as String: Keys.account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(oldQuery as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let session = try? JSONDecoder().decode(Session.self, from: data) else {
            return
        }

        // 新形式で保存
        try? save(session)

        // 旧エントリ削除
        let deleteOld: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Keys.service,
            kSecAttrAccount as String: Keys.account
        ]
        SecItemDelete(deleteOld as CFDictionary)
    }
}

// MARK: - Error

enum SessionStoreError: LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Keychain への保存に失敗しました (OSStatus: \(status))"
        }
    }
}
