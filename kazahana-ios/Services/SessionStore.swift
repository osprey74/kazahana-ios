// SessionStore.swift
// kazahana-ios
// Keychain を使ったセッション情報の永続化

import Foundation
import Security

/// セッション情報を Keychain に保存・取得・削除する
final class SessionStore {

    private enum Keys {
        static let service = "com.kazahana.app"
        static let account = "session"
    }

    // MARK: - 保存

    func save(_ session: Session) throws {
        let data = try JSONEncoder().encode(session)

        // 既存エントリを削除してから保存（update でも可だが、削除→追加が確実）
        delete()

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Keys.service,
            kSecAttrAccount as String: Keys.account,
            kSecValueData as String:   data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SessionStoreError.saveFailed(status)
        }
    }

    // MARK: - 取得

    func load() -> Session? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Keys.service,
            kSecAttrAccount as String: Keys.account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
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
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Keys.service,
            kSecAttrAccount as String: Keys.account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
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
