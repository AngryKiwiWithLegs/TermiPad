// M2b-2 输出脱敏（docs/m2b-remote-task-console-design.md §5.5）。
// 发送前的字面量模式替换：常见密钥/token 赋值形态 → ••••。
// 设计纪律：不自造密码学、不做语义理解——纯正则字面量族，硬编码不读
// 用户配置；漏脱风险由输出档位选择兜底（最敏感场景用 minimal）。
import Foundation

enum OutputRedactor {
    /// 替换占位符（固定，不给攻击者任何长度提示）。
    static let mask = "••••••••"

    /// 固定正则族（NSRegularExpression，不区分大小写）。覆盖：
    /// 1. 常见密钥名赋值：token/password/secret（含 client_secret 等
    ///    secret 后缀组合）/api_key/access_key/private_key = "value" / : "value"
    /// 2. Bearer / Basic 认证头
    /// 3. AWS AccessKeyId（20 位大写字母数字）
    /// 4. GitHub PAT（ghp_/gho_/ghu_/ghs_/ghr_ + 36 位字母数字）
    /// 5. Slack xoxb/xoxp 令牌
    /// 6. JWT 三段形态（header.payload.signature，各段 base64url ≥ 8 字符）
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

    /// 对输出片段做字面量脱敏。输入即 Mac 端捕获缓冲的截断片段。
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
