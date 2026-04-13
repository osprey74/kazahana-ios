// SessionStore.swift
// kazahana-ios
// Keychain を使ったマルチアカウント対応セッション情報の永続化

import Foundation
import Security

/// セッション情報を Keychain に保存・取得・削除する（マルチアカウント対応）
final class SessionStore {

    private enum Keys {
        static let service    = "com.osprey74.kazahana"
        static let accessGroup = "9L6A9KDH5P.com.osprey74.kazahana"
        /// App Groups UserDefaults のスイート名（Share Extension と共有）
        static let suiteName   = "group.com.osprey74.kazahana"
        static let savedDIDsKey = "savedAccountDIDs"
        static let activeDIDKey = "activeAccountDID"

        static func accountKey(for did: String) -> String { "session:\(did)" }
    }

    // MARK: - Shared UserDefaults（App Groups）

    private var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: Keys.suiteName) ?? .standard
    }

    // MARK: - Active Account DID

    /// 現在アクティブなアカウントの DID（Share Extension からも参照）
    var activeAccountDID: String? {
        get { sharedDefaults.string(forKey: Keys.activeDIDKey) }
        set { sharedDefaults.set(newValue, forKey: Keys.activeDIDKey) }
    }

    private var savedDIDs: [String] {
        get { sharedDefaults.stringArray(forKey: Keys.savedDIDsKey) ?? [] }
        set { sharedDefaults.set(newValue, forKey: Keys.savedDIDsKey) }
    }

    // MARK: - Init

    init() {
        migrateIfNeeded()
        migrateKeychainAccessibilityIfNeeded()
    }

    // MARK: - 保存

    func save(_ session: Session) throws {
        let data = try JSONEncoder().encode(session)
        let accountKey = Keys.accountKey(for: session.did)

        deleteFromKeychain(accountKey: accountKey)

        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      Keys.service,
            kSecAttrAccount as String:      accountKey,
            kSecAttrAccessGroup as String:  Keys.accessGroup,
            kSecValueData as String:        data,
            kSecAttrAccessible as String:   kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SessionStoreError.saveFailed(status)
        }

        if !savedDIDs.contains(session.did) {
            savedDIDs.append(session.did)
        }
        activeAccountDID = session.did
    }

    // MARK: - 取得

    /// アクティブアカウントのセッションを返す
    func load() -> Session? {
        guard let did = activeAccountDID else { return nil }
        return load(forDID: did)
    }

    /// DID を指定してセッションを返す
    func load(forDID did: String) -> Session? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      Keys.service,
            kSecAttrAccount as String:      Keys.accountKey(for: did),
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

    /// 保存済みの全セッションを返す
    func loadAll() -> [Session] {
        savedDIDs.compactMap { load(forDID: $0) }
    }

    // MARK: - 削除

    /// 指定 DID のセッションを削除する
    @discardableResult
    func delete(did: String) -> Bool {
        let result = deleteFromKeychain(accountKey: Keys.accountKey(for: did))
        savedDIDs.removeAll { $0 == did }
        if activeAccountDID == did {
            activeAccountDID = savedDIDs.first
        }
        return result
    }

    /// アクティブセッションを削除する（後方互換・ATProtoClient から呼ばれる）
    @discardableResult
    func delete() -> Bool {
        guard let did = activeAccountDID else { return true }
        return delete(did: did)
    }

    // MARK: - Private

    @discardableResult
    private func deleteFromKeychain(accountKey: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      Keys.service,
            kSecAttrAccount as String:      accountKey,
            kSecAttrAccessGroup as String:  Keys.accessGroup
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - マイグレーション（旧形式 → 新形式）

    /// Keychain アクセシビリティを ThisDeviceOnly から通常に変更する一回限りのマイグレーション
    /// Share Extension からのアクセス互換性を確保するために必要
    /// Note: SecItemUpdate は kSecAttrAccessible を変更できないため、削除→再追加で移行する
    private func migrateKeychainAccessibilityIfNeeded() {
        let migratedKey = "keychainAccessMigrated_v2"
        guard !sharedDefaults.bool(forKey: migratedKey) else { return }

        let searchQuery: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      Keys.service,
            kSecAttrAccessGroup as String:  Keys.accessGroup,
            kSecReturnData as String:       true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String:       kSecMatchLimitAll
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(searchQuery as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else {
            sharedDefaults.set(true, forKey: migratedKey)
            return
        }
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  let data = item[kSecValueData as String] as? Data else { continue }
            let deleteQuery: [String: Any] = [
                kSecClass as String:           kSecClassGenericPassword,
                kSecAttrService as String:     Keys.service,
                kSecAttrAccount as String:     account,
                kSecAttrAccessGroup as String: Keys.accessGroup
            ]
            SecItemDelete(deleteQuery as CFDictionary)
            let addQuery: [String: Any] = [
                kSecClass as String:           kSecClassGenericPassword,
                kSecAttrService as String:     Keys.service,
                kSecAttrAccount as String:     account,
                kSecAttrAccessGroup as String: Keys.accessGroup,
                kSecValueData as String:       data,
                kSecAttrAccessible as String:  kSecAttrAccessibleAfterFirstUnlock
            ]
            SecItemAdd(addQuery as CFDictionary, nil)
        }
        sharedDefaults.set(true, forKey: migratedKey)
    }

    /// 旧形式（account = "session"）から新形式（account = "session:{did}"）へ一回限り移行する
    private func migrateIfNeeded() {
        guard savedDIDs.isEmpty else { return }

        // accessGroup あり旧形式（直近バージョンの形式）
        if let session = loadLegacySession(withAccessGroup: true) {
            try? save(session)
            deleteLegacySession(withAccessGroup: true)
            return
        }
        // accessGroup なし旧形式（さらに古いバージョン）
        if let session = loadLegacySession(withAccessGroup: false) {
            try? save(session)
            deleteLegacySession(withAccessGroup: false)
        }
    }

    private func loadLegacySession(withAccessGroup: Bool) -> Session? {
        var query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  Keys.service,
            kSecAttrAccount as String:  "session",
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne
        ]
        if withAccessGroup {
            query[kSecAttrAccessGroup as String] = Keys.accessGroup
        }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let session = try? JSONDecoder().decode(Session.self, from: data) else {
            return nil
        }
        return session
    }

    private func deleteLegacySession(withAccessGroup: Bool) {
        var query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  Keys.service,
            kSecAttrAccount as String:  "session"
        ]
        if withAccessGroup {
            query[kSecAttrAccessGroup as String] = Keys.accessGroup
        }
        SecItemDelete(query as CFDictionary)
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
