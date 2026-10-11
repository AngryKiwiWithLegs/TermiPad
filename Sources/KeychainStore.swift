import Foundation
import Security

/// A minimal macOS Keychain wrapper. Used only for sensitive credentials; ordinary preferences stay in UserDefaults.
enum KeychainStore {
    private static let service = "com.termipad.app"

    static func string(for account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                throw KeychainStoreError.invalidStoredValue
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStoreError.operationFailed(status)
        }
    }

    static func save(_ value: String, for account: String) throws {
        let data = Data(value.utf8)
        // Delete the old item and create a new one (upsert + attribute migration): match/delete by primary key (class+service+
        // account) without accessible — it is an item attribute, not part of the primary key, and including it in the match makes
        // items with different legacy attributes "invisible" (2026-09-10 real-device test: after the iOS attribute migrated from
        // AfterFirstUnlock to WhenUnlockedThisDeviceOnly, update reported
        // NotFound and add collided with the old item with -25299, so saving the pairing always failed). The rebuilt item carries
        // the current platform's accessible value — the old item's outdated attribute is migrated in one step.
        SecItemDelete(itemMatchQuery(account: account) as CFDictionary)
        var item = baseQuery(account: account)
        item[kSecValueData as String] = data
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainStoreError.operationFailed(addStatus)
        }
    }

    static func remove(account: String) throws {
        // Deletion also matches by primary key (without accessible) — items with legacy attributes can be deleted too.
        let status = SecItemDelete(itemMatchQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.operationFailed(status)
        }
    }

    /// Item primary-key match (class + service + account) — used by update/delete/migration.
    private static func itemMatchQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // M2b defense line 1 (design §4): on iOS the pairing credentials are readable only while unlocked and
            // do not migrate to a new device with backups (a phone thief who wipes or swaps the device cannot get them); the Mac
            // keeps AfterFirstUnlock (desktop scenarios without a biometric-unlock constraint).
            kSecAttrAccessible as String: {
                #if os(iOS)
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                #else
                kSecAttrAccessibleAfterFirstUnlock
                #endif
            }()
        ]
    }
}

enum KeychainStoreError: LocalizedError, Equatable {
    case invalidStoredValue
    case operationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidStoredValue:
            return "The credential in the Keychain could not be read."
        case .operationFailed(let status):
            return "Keychain operation failed (status code: \(status))."
        }
    }
}
