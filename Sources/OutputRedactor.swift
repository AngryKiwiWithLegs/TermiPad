// M2b-2 output redaction (docs/m2b-remote-task-console-design.md §5.5).
// Literal pattern replacement before sending: common key/token assignment forms → ••••.
// Design discipline: no home-made cryptography, no semantic understanding — a pure family of regex literals, hard-coded and not read from
// user configuration; the risk of missed redaction is covered by the choice of output visibility (use minimal for the most sensitive scenarios).
import Foundation

enum OutputRedactor {
    /// Replacement placeholder (fixed, gives an attacker no length hint).
    static let mask = "••••••••"

    /// Fixed regex family (NSRegularExpression, case-insensitive). Covers:
    /// 1. Assignments to common secret names: token/password/secret (including client_secret and other
    ///    secret-suffix combinations)/api_key/access_key/private_key = "value" / : "value"
    /// 2. Bearer / Basic auth headers
    /// 3. AWS AccessKeyId (20 uppercase alphanumerics)
    /// 4. GitHub PAT (ghp_/gho_/ghu_/ghs_/ghr_ + 36 alphanumerics)
    /// 5. Slack xoxb/xoxp tokens
    /// 6. JWT three-part form (header.payload.signature, each part base64url ≥ 8 characters)
    private static let patterns: [String] = [
        #"(?i)\b(\w*token|\w*password|passwd|pwd|\w*secret|api[_-]?key|access[_-]?key|private[_-]?key)\b\s*[:=]\s*["']?[^\s"']{4,}"#,
        #"(?i)\b(bearer|basic)\s+[A-Za-z0-9_\-.+/=]{8,}"#,
        #"\b[A-Z0-9]{20}\b(?![A-Z0-9])"#,
        #"\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36}\b"#,
        #"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"#,
        #"\b[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#
    ]

    private static let compiled: [NSRegularExpression] = patterns.compactMap {
        try? NSRegularExpression(pattern: $0)
    }

    /// Apply literal redaction to an output snippet. The input is the truncated snippet from the Mac's capture buffer.
    static func redact(_ text: String) -> String {
        var result = text
        for regex in compiled {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, range: range, withTemplate: mask)
        }
        return result
    }
}
