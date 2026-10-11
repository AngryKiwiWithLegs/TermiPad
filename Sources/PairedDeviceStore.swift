// Credential-domain storage for M1 paired devices and the pairing identity (docs/m0-m1-mobile-entry-design.md §3.4,
// revised 2026-09-06). Design decision: device records and the identity private key live only in the Keychain, with no SwiftData
// entity — the Keychain naturally stays out of JSON backups (satisfying the §2.5 contract), and public-key fingerprints and device identity
// belong to the credential domain, on the same level as the API key.
// The storage backend is injectable: production uses KeychainMobileSecureStore; tests inject an in-memory implementation
// and never hit the real SecItem (consistent with the existing discipline of KeychainStoreTests).
import Foundation

protocol MobileSecureKeyValueStore: Sendable {
    func string(for account: String) throws -> String?
    func save(_ value: String, for account: String) throws
    func remove(account: String) throws
}

/// Production backend: delegates everything to KeychainStore (kSecAttrService = com.termipad.app).
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

/// The minimal local record of one paired iPhone. publicKeyHash is the SHA-256 fingerprint of the phone's public key
/// and contains no commands, paths, variables, or any tool data.
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

    // MARK: - Paired device records

    static func list(store: MobileSecureKeyValueStore = KeychainMobileSecureStore()) -> [PairedDeviceRecord] {
        let decoder = recordDecoder()
        return indexedIDs(store: store).compactMap { id in
            record(id: id, store: store, decoder: decoder)
        }
    }

    /// The device IDs in the index item. A record only counts as stored while its ID is listed here.
    private static func indexedIDs(store: MobileSecureKeyValueStore) -> [UUID] {
        guard let indexJSON = try? store.string(for: indexAccount),
              let indexData = indexJSON.data(using: .utf8),
              let ids = try? JSONDecoder().decode([UUID].self, from: indexData) else {
            return []
        }
        return ids
    }

    private static func recordDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func record(
        id: UUID,
        store: MobileSecureKeyValueStore,
        decoder: JSONDecoder
    ) -> PairedDeviceRecord? {
        guard let recordJSON = try? store.string(for: deviceAccount(id)),
              let recordData = recordJSON.data(using: .utf8) else {
            return nil
        }
        return try? decoder.decode(PairedDeviceRecord.self, from: recordData)
    }

    /// A revoked device (revokedAt non-nil) disappears from the active set immediately — this is the data plane of the §7 red line "every permission is revocable".
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
        // Orphan cleanup (multi-device semantics are kept — the user can pair an iPhone and an iPad at the same time):
        // (a) revoked records — keychain items that live forever after revocation only pile up authorization prompts
        //     (2026-09-10 real device: 12 orphan items made the user enter the password a dozen times in a row);
        //     a revoked device can only come back by pairing again (the trust anchor is broken, so keeping the data is pointless);
        // (b) old records with the same fingerprint — the new record from re-pairing the same device replaces the old one.
        // The new index is built from this one pass instead of reading every Keychain item a second time
        // (each read can raise an authorization prompt). It lists exactly what a second read would find:
        // active records that were kept, plus an active record whose removal failed and which is therefore still stored.
        var ids: [UUID] = []
        for existing in list(store: store) {
            if existing.revokedAt != nil || existing.publicKeyHash == record.publicKeyHash {
                let wasRemoved = (try? store.remove(account: deviceAccount(existing.id))) != nil
                if wasRemoved || existing.revokedAt != nil { continue }
            }
            ids.append(existing.id)
        }
        ids.append(record.id)
        try store.save(try encode(record), for: deviceAccount(record.id))
        try store.save(try encode(ids), for: indexAccount)
        return record
    }

    /// Reads the index and the one requested record. Going through `list` would read every paired device's
    /// Keychain item on each lookup, and this runs for every reconnect from the phone.
    static func find(id: UUID, store: MobileSecureKeyValueStore = KeychainMobileSecureStore()) -> PairedDeviceRecord? {
        guard indexedIDs(store: store).contains(id) else { return nil }
        return record(id: id, store: store, decoder: recordDecoder())
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

    // MARK: - Mac pairing identity

    /// The Mac's X25519 identity: generated and written to the Keychain on first call, then the same private key is reused.
    /// If the stored content is corrupted (base64 cannot be decoded), regenerate and overwrite — losing the identity only means pairing again,
    /// not losing data.
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

    // MARK: - Private

    private static func encode(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
