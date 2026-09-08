// M1 已配对设备与配对身份的凭据域存储（docs/m0-m1-mobile-entry-design.md §3.4，
// 2026-09-06 修订）。设计决定：设备记录与身份私钥只存 Keychain、不建 SwiftData
// 实体——Keychain 天然不进 JSON 备份（满足 §2.5 契约），公钥指纹与设备身份
// 属于凭据域，与 API Key 同级。
// 存储后端可注入：生产走 KeychainMobileSecureStore；测试注入内存实现，
// 不打真实 SecItem（与 KeychainStoreTests 的既有纪律一致）。
import Foundation

protocol MobileSecureKeyValueStore: Sendable {
    func string(for account: String) throws -> String?
    func save(_ value: String, for account: String) throws
    func remove(account: String) throws
}

/// 生产后端：全部委托 KeychainStore（kSecAttrService = com.termipad.app）。
struct KeychainMobileSecureStore: MobileSecureKeyValueStore {
    func string(for account: String) throws -> String? {
        try KeychainStore.string(for: account)
    }

    func save(_ value: String, for account: String) throws {
        try KeychainStore.save(value, for: account)
    }

    func remove(account: String) throws {
        try KeychainStore.remove(account: account)
    }
}

/// 一台已配对 iPhone 的最小本地记录。publicKeyHash 是手机公钥的 SHA-256 指纹，
/// 不含命令、路径、变量或任何工具数据。
struct PairedDeviceRecord: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let displayName: String
    let publicKeyHash: String
    let pairedAt: Date
    var lastConnectedAt: Date?
    var revokedAt: Date?
}

enum PairedDeviceStore {
    static let indexAccount = "mobile-pairing.device-index"
    static let identityAccount = "mobile-pairing.identity"

    static func deviceAccount(_ id: UUID) -> String {
        "mobile-pairing.device.\(id.uuidString)"
    }

    // MARK: - 已配对设备记录

    static func list(store: MobileSecureKeyValueStore = KeychainMobileSecureStore()) -> [PairedDeviceRecord] {
        guard let indexJSON = try? store.string(for: indexAccount),
              let indexData = indexJSON.data(using: .utf8),
              let ids = try? JSONDecoder().decode([UUID].self, from: indexData) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return ids.compactMap { id in
            guard let recordJSON = try? store.string(for: deviceAccount(id)),
                  let recordData = recordJSON.data(using: .utf8),
                  let record = try? decoder.decode(PairedDeviceRecord.self, from: recordData) else {
                return nil
            }
            return record
        }
    }

    /// 撤销（revokedAt 非空）的设备立即从活跃集合消失——这是 §7 红线"每个权限可撤销"的数据面。
    static func activeDevices(store: MobileSecureKeyValueStore = KeychainMobileSecureStore()) -> [PairedDeviceRecord] {
        list(store: store).filter { $0.revokedAt == nil }
    }

    @discardableResult
    static func add(
        displayName: String,
        publicKeyData: Data,
        store: MobileSecureKeyValueStore = KeychainMobileSecureStore()
    ) throws -> PairedDeviceRecord {
        let record = PairedDeviceRecord(
            id: UUID(),
            displayName: displayName,
            publicKeyHash: MobilePairingCrypto.fingerprint(forPublicKeyData: publicKeyData),
            pairedAt: Date(),
            lastConnectedAt: nil,
            revokedAt: nil)
        var ids = list(store: store).map(\.id)
        ids.append(record.id)
        try store.save(try encode(record), for: deviceAccount(record.id))
        try store.save(try encode(ids), for: indexAccount)
        return record
    }

    static func find(id: UUID, store: MobileSecureKeyValueStore = KeychainMobileSecureStore()) -> PairedDeviceRecord? {
        list(store: store).first { $0.id == id }
    }

    static func findActive(
        byPublicKeyHash publicKeyHash: String,
        store: MobileSecureKeyValueStore = KeychainMobileSecureStore()
    ) -> PairedDeviceRecord? {
        activeDevices(store: store).first { $0.publicKeyHash == publicKeyHash }
    }

    static func revoke(id: UUID, store: MobileSecureKeyValueStore = KeychainMobileSecureStore()) throws {
        guard var record = find(id: id, store: store) else { return }
        record.revokedAt = Date()
        try store.save(try encode(record), for: deviceAccount(id))
    }

    static func markConnected(
        id: UUID,
        at date: Date = Date(),
        store: MobileSecureKeyValueStore = KeychainMobileSecureStore()
    ) throws {
        guard var record = find(id: id, store: store) else { return }
        record.lastConnectedAt = date
        try store.save(try encode(record), for: deviceAccount(id))
    }

    static func removeAll(store: MobileSecureKeyValueStore = KeychainMobileSecureStore()) throws {
        for id in list(store: store).map(\.id) {
            try store.remove(account: deviceAccount(id))
        }
        try store.remove(account: indexAccount)
    }

    // MARK: - Mac 端配对身份

    /// Mac 端 X25519 身份：首次调用生成并写入 Keychain，之后复用同一私钥。
    /// 存储内容损坏（base64 解不开）时重新生成并覆盖——身份丢失只意味着重新配对，
    /// 不是数据丢失。
    enum MobilePairingIdentityStore {
        static func loadOrCreate(
            store: MobileSecureKeyValueStore = KeychainMobileSecureStore()
        ) throws -> MobilePairingIdentity {
            if let existing = try store.string(for: identityAccount),
               let keyData = Data(base64Encoded: existing), !keyData.isEmpty {
                return MobilePairingIdentity(privateKeyData: keyData)
            }
            let identity = MobilePairingIdentity.generate()
            try store.save(identity.privateKeyData.base64EncodedString(), for: identityAccount)
            return identity
        }
    }

    // MARK: - 私有

    private static func encode(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
