// Protocol layer of M1 local network pairing (docs/m0-m1-mobile-entry-design.md §3.3-§3.4).
// This file only handles protocol data and the handshake state machine — data minimization is guaranteed by the hard-coded struct fields:
// the phone cannot send commands, paths, arguments, or environment variables, and cannot receive them either.
// Real network listening (NWListener) is wired in by the future Sources/MobilePairingService.swift;
// this file stays zero-I/O, enforced by the mobile_pairing_protocol_code guard in verify-macos.sh.
import CryptoKit
import Foundation
import Network

/// M1 operation allowlist (§3.4): every iPhone request must match one of these, otherwise it is rejected.
/// Same discipline as TaskMCPBridge's restricted case design — the allowlist is the attack surface.
enum PairedDeviceOperation: String, Codable, CaseIterable, Sendable {
    case listTools
    case requestLaunch
    case listScopes
    case listFixedTasks
    case requestTaskProposal
    case getTaskStatus
    case cancelTask
    case heartbeat
    // M4 interactive sessions (docs/m4-interactive-session-design.md §2.1):
    // subscription-style long-lived connection — after openTaskStream the connection stays up and the Mac pushes the stream;
    // closeTaskStream unsubscribes. Precondition: the daily remote window is open.
    case openTaskStream
    case closeTaskStream
    /// M4-3: return of the interaction choice (taskIntentID + interactionSelection).
    case respondInteraction
}

/// Minimal payload of an iPhone → Mac request. The field set is a product red line (minimal data return):
/// no commit may add a command/path/parameter/environment field —
/// MobilePairingProtocolTests locks down the encoded key set.
/// M2b increment (docs/m2b-remote-task-console-design.md §3.1): the three task reference
/// fields are all UUIDs / allowlisted enum strings and only meaningful for task operations —
/// requestTaskProposal uses taskKind+projectScopeID (referencing FixedTaskCatalog
/// and a registered scope, no path is sent), and getTaskStatus/cancelTask use taskIntentID.
/// Optional + synthesized Codable (decodeIfPresent semantics) — old phones and Macs stay compatible both ways.
struct MobilePairingRequest: Codable, Sendable, Equatable {
    let operation: PairedDeviceOperation
    let requestID: UUID
    /// nil only for target-less operations such as listTools / heartbeat.
    let toolID: UUID?
    var taskKind: String? = nil
    var projectScopeID: UUID? = nil
    var taskIntentID: UUID? = nil
    /// M4: resume offset for openTaskStream (reconnect after a drop) — pushing continues after this UTF-8 byte
    /// offset; nil = a brand-new subscription. Ignored by old peers (compatibility red line).
    var streamResumeOffset: Int? = nil
    /// M4-3: the option selected at the interaction point (used by respondInteraction).
    var interactionSelection: String? = nil
}

/// Mac → iPhone tool catalog entry: the phone is only allowed to see these 4 fields.
struct MobileToolSummary: Codable, Sendable, Equatable {
    let id: UUID
    let displayName: String
    let displayDescription: String
    let iconSymbolName: String?
}

/// AEAD envelope: the JSON payload is encrypted with the session key before transport.
enum MobilePairingEnvelope {
    static func seal(_ value: some Encodable, using key: SymmetricKey) throws -> Data {
        let data = try JSONEncoder().encode(value)
        return try MobilePairingCrypto.seal(data, using: key)
    }

    static func openRequest(_ data: Data, using key: SymmetricKey) throws -> MobilePairingRequest {
        let plaintext = try MobilePairingCrypto.open(data, using: key)
        return try JSONDecoder().decode(MobilePairingRequest.self, from: plaintext)
    }

    static func openToolSummaries(_ data: Data, using key: SymmetricKey) throws -> [MobileToolSummary] {
        let plaintext = try MobilePairingCrypto.open(data, using: key)
        return try JSONDecoder().decode([MobileToolSummary].self, from: plaintext)
    }

    static func openAck(_ data: Data, using key: SymmetricKey) throws -> MobilePairingAck {
        let plaintext = try MobilePairingCrypto.open(data, using: key)
        return try JSONDecoder().decode(MobilePairingAck.self, from: plaintext)
    }

    static func openLaunchResponse(_ data: Data, using key: SymmetricKey) throws -> MobileLaunchResponse {
        let plaintext = try MobilePairingCrypto.open(data, using: key)
        return try JSONDecoder().decode(MobileLaunchResponse.self, from: plaintext)
    }

    // MARK: M2b task session envelope decoding (same pattern as the existing open*)

    static func openScopeSummaries(_ data: Data, using key: SymmetricKey) throws -> [MobileScopeSummary] {
        let plaintext = try MobilePairingCrypto.open(data, using: key)
        return try JSONDecoder().decode([MobileScopeSummary].self, from: plaintext)
    }

    static func openFixedTaskSummaries(_ data: Data, using key: SymmetricKey) throws -> [MobileFixedTaskSummary] {
        let plaintext = try MobilePairingCrypto.open(data, using: key)
        return try JSONDecoder().decode([MobileFixedTaskSummary].self, from: plaintext)
    }

    static func openSessionEntries(_ data: Data, using key: SymmetricKey) throws -> [MobileSessionEntry] {
        let plaintext = try MobilePairingCrypto.open(data, using: key)
        return try JSONDecoder().decode([MobileSessionEntry].self, from: plaintext)
    }

    static func openTaskProposalResponse(_ data: Data, using key: SymmetricKey) throws -> MobileTaskProposalResponse {
        let plaintext = try MobilePairingCrypto.open(data, using: key)
        return try JSONDecoder().decode(MobileTaskProposalResponse.self, from: plaintext)
    }

    // MARK: M4 interactive session envelope decoding

    static func openStreamResponse(_ data: Data, using key: SymmetricKey) throws -> MobileStreamResponse {
        let plaintext = try MobilePairingCrypto.open(data, using: key)
        return try JSONDecoder().decode(MobileStreamResponse.self, from: plaintext)
    }

    static func openStreamChunk(_ data: Data, using key: SymmetricKey) throws -> MobileStreamChunk {
        let plaintext = try MobilePairingCrypto.open(data, using: key)
        return try JSONDecoder().decode(MobileStreamChunk.self, from: plaintext)
    }

    static func openStreamStateChange(_ data: Data, using key: SymmetricKey) throws -> MobileStreamStateChange {
        let plaintext = try MobilePairingCrypto.open(data, using: key)
        return try JSONDecoder().decode(MobileStreamStateChange.self, from: plaintext)
    }

    static func openStreamInteraction(_ data: Data, using key: SymmetricKey) throws -> MobileStreamInteraction {
        let plaintext = try MobilePairingCrypto.open(data, using: key)
        return try JSONDecoder().decode(MobileStreamInteraction.self, from: plaintext)
    }
}

/// Mac → iPhone pairing confirmation (sent after AEAD encryption with the session key).
struct MobilePairingAck: Codable, Sendable, Equatable {
    let accepted: Bool
    let deviceID: UUID
}

/// Mac → iPhone launch request result (§3.3.2). The phone receives only the result enum and an optional
/// one-line hint, never the command body / paths / variables / terminal output.
struct MobileLaunchResponse: Codable, Sendable, Equatable {
    enum Status: String, Codable, Sendable {
        case accepted
        case rejected
    }

    let status: Status
    /// One-sentence plain-language reason on rejection (fixed enum copy, contains no tool data).
    let reason: String?
}

// MARK: - M2b task session return data (docs/m2b-remote-task-console-design.md §3.2)
// Same data-minimization discipline as the M1 catalog: the phone sees only references, display names, and fixed enums,
// never rootPath / commands / arguments / variables / the terminal output of tool launches.

/// Project scope entry: id + display name (rootPath is never sent — the scope path is local data).
struct MobileScopeSummary: Codable, Sendable, Equatable {
    let id: UUID
    let displayName: String
}

/// Fixed task catalog entry: kind + bilingual purpose + fixed command preview (all
/// FixedTaskCatalog literals, not user data; task submission returns only the kind reference).
struct MobileFixedTaskSummary: Codable, Sendable, Equatable {
    let kind: String
    let purpose: String
    let commandPreview: String
    /// M2c: the task's fixed requirements for the project directory (FixedTaskCatalog literals, not user
    /// data) — the phone shows "Requires: Package.swift" and the like, so the user can match
    /// scopes to tasks themselves (2026-09-15 test: the missing-file rejection copy became precise, but when choosing a scope
    /// there was still no way to know which scope satisfies which task). Optional + synthesized decoding — old Macs
    /// do not send this key and old phones ignore it (compatibility red line).
    var requiredRelativePaths: [String]? = nil
}

/// Session entry: one shape for tool launches and fixed tasks (§3.3 — every status string comes from the
/// raw T1 TaskExecutionState enum; tool launches only use launched/launchFailed).
struct MobileSessionEntry: Codable, Sendable, Equatable, Identifiable {
    enum SessionKind: String, Codable, Sendable {
        case toolLaunch
        case fixedTask
    }

    let id: UUID
    let title: String
    let kind: SessionKind
    let executionState: String
    let exitCode: Int?
    let startedAt: Date?
    let finishedAt: Date?
    /// Non-nil only when the output visibility is ≥ restricted and the entry is a T1 fixed task (§5.4);
    /// tool launches (the terminal handoff path) never have output.
    var outputSnippet: String? = nil
}

/// Receipt for requestTaskProposal: accept/reject + task reference (rejection copy is a fixed enum).
struct MobileTaskProposalResponse: Codable, Sendable, Equatable {
    enum Status: String, Codable, Sendable {
        case accepted
        case rejected
    }

    let status: Status
    /// One-sentence plain-language reason on rejection (fixed enum copy, no paths and no commands).
    let reason: String?
    /// On acceptance, the task reference the phone uses for later getTaskStatus / cancelTask calls.
    let taskIntentID: UUID?
}

// MARK: - M4 interactive session pushes (docs/m4-interactive-session-design.md §2.1)
// Frames pushed proactively from the Mac to the phone (inside the subscription-style long-lived connection). All go through the existing AEAD envelope;
// output is redacted by OutputRedactor first; tool launches (terminal handoff) never have a stream.

/// Stream subscription receipt: accepted (with a cursor — the starting point for resuming after a drop) or rejected.
struct MobileStreamResponse: Codable, Sendable, Equatable {
    enum Status: String, Codable, Sendable {
        case accepted
        case rejected
    }

    let status: Status
    let reason: String?
    /// Resume cursor: push output starting after this offset (bytes); 0 for a new subscription.
    let resumeOffset: Int?
}

/// Output chunk push (Mac → phone, many times over the stream's lifetime).
struct MobileStreamChunk: Codable, Sendable, Equatable {
    let streamID: UUID
    /// Start of the byte range covered by this chunk (basis for the resume cursor).
    let offset: Int
    /// Redacted output text (line-level framing, ≤8KB per chunk).
    let text: String
}

/// State change push.
struct MobileStreamStateChange: Codable, Sendable, Equatable {
    let streamID: UUID
    let executionState: String
    let exitCode: Int?
    let finishedAt: Date?
}

/// Interaction point push (M4-3): the task needs a decision. All options come from task-definition literals.
struct MobileStreamInteraction: Codable, Sendable, Equatable {
    let streamID: UUID
    let prompt: String
    /// Fixed options (declared by the task definition, not generated at runtime).
    let options: [String]
}

/// Persisted phone-side credentials (formerly a private CompanionApp type, moved into the shared protocol layer in M2a —
/// so Mac tests can lock down its encode/decode compatibility, a single source of truth for both sides; Keychain storage on iOS is unchanged).
/// `tailnetEndpoint` (M2a): issued by MacResumeHello during a same-network resume and persisted,
/// for connecting directly to "100.x.x.x:57147" when away. Optional + synthesized Codable uses
/// decodeIfPresent for Optionals — old credential JSON without this key still decodes (restore compatibility red line, locked by tests).
struct CompanionPairingCredentials: Codable, Sendable, Equatable {
    let deviceID: UUID
    let macPublicKey: Data
    let macFingerprint: String
    let deviceName: String
    var tailnetEndpoint: String? = nil
}

/// Frame codec with a 4-byte big-endian length prefix. Pure logic — fragmentation/coalescing is covered by tests;
/// the network layer only "receives bytes into a buffer, decodes one frame, sends one frame".
enum MobilePairingFrame {
    static let headerByteCount = 4
    /// Single-frame limit of 64 KB: pairing and tool catalog messages are far smaller; declaring more is a protocol violation and disconnects immediately.
    static let maxPayloadByteCount = 65_536

    enum DecodeOutcome: Equatable {
        case message(Data, remainder: Data)
        case incomplete
        case invalid
    }

    static func encode(_ payload: Data) -> Data {
        var frame = Data(capacity: headerByteCount + payload.count)
        let length = UInt32(payload.count)
        frame.append(UInt8((length >> 24) & 0xFF))
        frame.append(UInt8((length >> 16) & 0xFF))
        frame.append(UInt8((length >> 8) & 0xFF))
        frame.append(UInt8(length & 0xFF))
        frame.append(payload)
        return frame
    }

    static func decodeOne(from buffer: Data) -> DecodeOutcome {
        guard buffer.count >= headerByteCount else { return .incomplete }
        let header = [UInt8](buffer.prefix(headerByteCount))
        let declaredLength = (UInt32(header[0]) << 24)
            | (UInt32(header[1]) << 16)
            | (UInt32(header[2]) << 8)
            | UInt32(header[3])
        guard declaredLength <= maxPayloadByteCount else { return .invalid }
        let total = headerByteCount + Int(declaredLength)
        guard buffer.count >= total else { return .incomplete }
        let message = Data(buffer.dropFirst(headerByteCount).prefix(Int(declaredLength)))
        let remainder = Data(buffer.dropFirst(total))
        return .message(message, remainder: remainder)
    }
}

/// Bonjour advertisement contract: the service type is fixed and not configurable at runtime — prevents redirection to a spoofed service.
/// TXT advertises only the protocol version + fingerprint prefix + LAN direct address (a/p, so the phone can bypass iOS 26's
/// stuck resolution of .service endpoints); it does not advertise the host name, user name, or tool information.
extension MobilePairingCrypto {
    static let bonjourServiceType = "_termipad-m1._tcp"
    static let bonjourServiceName = "TermiPad"
    /// Fixed M1 listening port (the Mac listens on it; the phone appends it when recovering the direct address from the instance name).
    /// Shared across both sides, hence placed in the protocol layer.
    static let listenerPort: UInt16 = 57146
    /// Fixed listening port for the M2a remote tunnel (Mac loopback listener + tailscale serve TCP forwarding;
    /// independent of M1's 57146 — the two paths do not interfere, can be toggled separately, and have isolated failure domains).
    static let tunnelListenerPort: UInt16 = 57147

    static func bonjourTXTRecord(fingerprint: String) -> [String: String] {
        [
            "v": protocolVersion,
            "fp": String(fingerprint.prefix(16))
        ]
    }

    /// Whether the TXT carries a direct address ("a"=IPv4, "p"=port) — the phone uses it to decide between
    /// a direct hostPort connection and falling back to .service endpoint resolution.
    static func bonjourDirectAddress(fromTXT txt: NWTXTRecord) -> (host: String, port: UInt16)? {
        guard let host = txt["a"], let portString = txt["p"],
              let port = UInt16(portString), !host.isEmpty else {
            return nil
        }
        return (host, port)
    }
}

/// Mac-side state machine of the pairing handshake (§3.3 steps 3-6). Pure logic: real send/receive is driven by the network layer,
/// and tests complete the full handshake with both ends simulated in-process.
enum MobilePairingHandshake {
    static let currentProtocolVersion = MobilePairingCrypto.protocolVersion
    static let resumeProtocolInfo = "termipad-m1-resume-v1"

    /// Mac → iPhone step one: announce the protocol version, public key, nonce, and fingerprint (compared by eye on the iPhone screen).
    struct MacHello: Codable, Sendable, Equatable {
        let protocolVersion: String
        let macPublicKey: Data
        let macNonce: Data
        let fingerprint: String
    }

    /// iPhone → Mac step two: phone public key + nonce + the pairing code the user copied + device name.
    struct PhoneHello: Codable, Sendable, Equatable {
        let protocolVersion: String
        let phonePublicKey: Data
        let phoneNonce: Data
        let pairingCode: String
        let deviceName: String
    }

    /// What the Mac produces after accepting a pairing: the session key + the minimal record to write to PairedDeviceStore.
    struct AcceptedPairing: Sendable, Equatable {
        let sessionKeyData: Data
        let phonePublicKeyHash: String
        let deviceName: String
    }

    static func makeMacHello(identity: MobilePairingIdentity, macNonce: Data) throws -> MacHello {
        guard macNonce.count == MobilePairingCrypto.nonceByteCount else {
            throw MobilePairingError.invalidNonce
        }
        let publicKey = try identity.publicKeyData()
        return MacHello(
            protocolVersion: currentProtocolVersion,
            macPublicKey: publicKey,
            macNonce: macNonce,
            fingerprint: MobilePairingCrypto.fingerprint(forPublicKeyData: publicKey))
    }

    static func acceptPhoneHello(
        _ hello: PhoneHello,
        identity: MobilePairingIdentity,
        macNonce: Data
    ) throws -> AcceptedPairing {
        // The protocol version is pinned exactly (same discipline as MCP initialize version negotiation) — "a higher version" is not accepted.
        guard hello.protocolVersion == currentProtocolVersion else {
            throw MobilePairingError.unsupportedProtocolVersion
        }
        guard hello.pairingCode.utf8.count == MobilePairingCrypto.pairingCodeDigitCount else {
            throw MobilePairingError.invalidPairingCode
        }
        guard hello.phoneNonce.count == MobilePairingCrypto.nonceByteCount,
              macNonce.count == MobilePairingCrypto.nonceByteCount else {
            throw MobilePairingError.invalidNonce
        }
        guard !hello.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MobilePairingError.invalidDeviceName
        }
        let key = try identity.sessionKey(
            peerPublicKeyData: hello.phonePublicKey,
            pairingCode: hello.pairingCode,
            macNonce: macNonce,
            phoneNonce: hello.phoneNonce)
        return AcceptedPairing(
            sessionKeyData: key.withUnsafeBytes { Data($0) },
            phonePublicKeyHash: MobilePairingCrypto.fingerprint(forPublicKeyData: hello.phonePublicKey),
            deviceName: hello.deviceName)
    }

    // MARK: - Session resume (§3.3.1, added 2026-09-06)

    /// First frame when an already-paired phone reconnects. No pairingCode field — distinguished from PhoneHello by its fields.
    struct PhoneResumeHello: Codable, Sendable, Equatable {
        let protocolVersion: String
        let deviceID: UUID
        let phonePublicKey: Data
        let phoneNonce: Data
    }

    /// Plaintext hello the Mac returns to a paired phone (public key and nonce are not secret; all later frames use AEAD).
    /// M2a addition: `tailnetEndpoint` is non-nil only when "Remote Access" is turned on on the Mac
    /// ("100.x.x.x:57147"). Plaintext is acceptable — the confidentiality of the tailnet IP is inherently protected by tailnet
    /// membership, non-members cannot route to 100.64/10; the connection still needs both app-layer pairing checks to pass.
    /// Old Macs do not send this field (decodes to nil); old phones ignore unknown keys — compatible both ways.
    struct MacResumeHello: Codable, Sendable, Equatable {
        let protocolVersion: String
        let macPublicKey: Data
        let macNonce: Data
        var tailnetEndpoint: String? = nil
    }

    /// Dispatch result for the first hello the Mac receives.
    enum IncomingHello {
        case pairing(PhoneHello)
        case resume(PhoneResumeHello)
    }

    /// Tell the two hellos apart by which JSON fields exist: has pairingCode → pairing; has deviceID → resume.
    static func decodeIncomingHello(from data: Data) -> IncomingHello? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if object["pairingCode"] != nil {
            return (try? JSONDecoder().decode(PhoneHello.self, from: data)).map { .pairing($0) }
        }
        if object["deviceID"] != nil {
            return (try? JSONDecoder().decode(PhoneResumeHello.self, from: data)).map { .resume($0) }
        }
        return nil
    }

    /// Mac-side resume validation + session key derivation. Split into two steps so that iOS can also reuse the pure computation:
    /// 1. `validateResumeRecord`: triple binding of version/record/fingerprint (Mac only, depends on PairedDeviceRecord)
    /// 2. `resumeSessionKey`: pure computation; identical signatures on both sides yield the same key
    ///
    /// Overall equivalent to the original `acceptResume` + `expectedRecord.revokedAt == nil` + public-key fingerprint check.
    /// The point of the split is to let iOS reuse the handshake code without pulling in the Mac-only PairedDeviceRecord type.

    /// Pure computation side: pinned version + session key derivation. iOS calls this after the two-way public-key fingerprint binding.
    /// The Mac calls `validateResumeRecord` first and then this method — the two steps are equivalent to the original `acceptResume`.
    static func deriveResumeSessionKey(
        _ hello: PhoneResumeHello,
        identity: MobilePairingIdentity,
        macNonce: Data
    ) throws -> Data {
        guard hello.protocolVersion == currentProtocolVersion else {
            throw MobilePairingError.unsupportedProtocolVersion
        }
        guard hello.phoneNonce.count == MobilePairingCrypto.nonceByteCount,
              macNonce.count == MobilePairingCrypto.nonceByteCount else {
            throw MobilePairingError.invalidNonce
        }
        let key = try identity.resumeSessionKey(
            peerPublicKeyData: hello.phonePublicKey,
            macNonce: macNonce,
            phoneNonce: hello.phoneNonce)
        return key.withUnsafeBytes { Data($0) }
    }
}
