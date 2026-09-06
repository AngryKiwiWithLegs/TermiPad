// 手机端配对凭据（docs/m0-m1-mobile-entry-design.md §3.3.1）。
// 持久化三件套：长期 X25519 身份（替代临时身份）、Mac 公钥+指纹（初次配对
// 人工比对的信任锚点）、deviceID。全部经 KeychainStore（iOS 同一 Security API）。
import Foundation

struct CompanionPairingCredentials: Codable, Sendable, Equatable {
    let deviceID: UUID
    let macPublicKey: Data
    let macFingerprint: String
    let deviceName: String
}

enum CompanionPairingStore {
    static let identityAccount = "companion.identity"
    static let credentialsAccount = "companion.credentials"

    static func hasCredentials() -> Bool {
        guard let identityJSON = try? KeychainStore.string(for: identityAccount),
              Data(base64Encoded: identityJSON) != nil,
              let credentialsJSON = try? KeychainStore.string(for: credentialsAccount),
              let credentialsData = credentialsJSON.data(using: .utf8),
              (try? JSONDecoder().decode(CompanionPairingCredentials.self, from: credentialsData)) != nil
        else { return false }
        return true
    }

    static func save(identity: MobilePairingIdentity, credentials: CompanionPairingCredentials) throws {
        try KeychainStore.save(identity.privateKeyData.base64EncodedString(), for: identityAccount)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(credentials)
        try KeychainStore.save(String(data: data, encoding: .utf8) ?? "", for: credentialsAccount)
    }

    static func loadIdentity() -> MobilePairingIdentity? {
        guard let base64 = try? KeychainStore.string(for: identityAccount),
              let keyData = Data(base64Encoded: base64), !keyData.isEmpty else {
            return nil
        }
        return MobilePairingIdentity(privateKeyData: keyData)
    }

    static func loadCredentials() -> CompanionPairingCredentials? {
        guard let json = try? KeychainStore.string(for: credentialsAccount),
              let data = json.data(using: .utf8),
              let credentials = try? JSONDecoder().decode(CompanionPairingCredentials.self, from: data) else {
            return nil
        }
        return credentials
    }

    /// 解除配对 / 凭据失效时清除——手机端回到未配对状态，可重新走配对流程。
    static func clear() {
        try? KeychainStore.remove(account: identityAccount)
        try? KeychainStore.remove(account: credentialsAccount)
    }
}
