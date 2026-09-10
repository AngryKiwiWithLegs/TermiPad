import Foundation
import Security

/// 极简的 macOS Keychain 封装。仅用于敏感凭据；普通偏好继续保存在 UserDefaults。
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
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainStoreError.operationFailed(updateStatus)
        }

        var item = query
        item[kSecValueData as String] = data
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainStoreError.operationFailed(addStatus)
        }
    }

    static func remove(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.operationFailed(status)
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // M2b 防线 1（设计 §4）：iOS 端配对凭据只在解锁状态下可读且
            // 不随备份迁移到新设备（偷手机者刷机/换机拿不到凭据）；Mac 端
            // 维持 AfterFirstUnlock（桌面无生物识别解锁约束的场景）。
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
            return "Keychain 中的凭据无法读取。"
        case .operationFailed(let status):
            return "Keychain 操作失败（状态码：\(status)）。"
        }
    }
}
