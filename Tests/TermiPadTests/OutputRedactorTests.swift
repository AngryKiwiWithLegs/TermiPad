import XCTest
@testable import TermiPad

/// M2b-2 输出脱敏契约（docs/m2b-remote-task-console-design.md §5.5）：
/// 六个正则族每族至少一例必须命中替换；普通文本必须原样保留。
/// 这是"输出档位上线的前置守卫"（设计 §7.4）。
final class OutputRedactorTests: XCTestCase {

    func testRedactsTokenStyleAssignments() {
        let cases = [
            "GITHUB_TOKEN=ghp_abcdefghijklmnopqrstuvwxyz1234567890",
            "api_key: sk-live-abcdef123456",
            "API_KEY=\"abcdef123456\"",
            "password = hunter2secret",
            "client_secret: 8f3a9c2b7d1e"
        ]
        for input in cases {
            let output = OutputRedactor.redact(input)
            XCTAssertFalse(output.contains("ghp_") || output.contains("sk-live"),
                           "未脱敏：\(input) → \(output)")
            XCTAssertTrue(output.contains(OutputRedactor.mask), "应有掩码：\(input) → \(output)")
        }
    }

    func testRedactsAuthHeaders() {
        let output = OutputRedactor.redact("Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVNHj0")
        XCTAssertTrue(output.contains(OutputRedactor.mask))
        XCTAssertFalse(output.contains("eyJhbGciOiJIUzI1NiJ9"))
    }

    func testRedactsAwsAccessKeyIds() {
        let output = OutputRedactor.redact("AKIAIOSFODNN7EXAMPLE remaining")
        XCTAssertTrue(output.contains(OutputRedactor.mask))
        XCTAssertFalse(output.contains("AKIAIOSFODNN7EXAMPLE"))
    }

    func testRedactsGithubPats() {
        let output = OutputRedactor.redact("pat=ghp_16C7e42F292c6912E7710c838347Ae178B4a")
        XCTAssertFalse(output.contains("ghp_"))
        XCTAssertTrue(output.contains(OutputRedactor.mask))
    }

    func testRedactsSlackTokens() {
        let output = OutputRedactor.redact("SLACK_TOKEN=xoxb-123456789012-1234567890123-AbCdEfGhIjKlMnOpQrStUvWx")
        XCTAssertFalse(output.contains("xoxb-"))
        XCTAssertTrue(output.contains(OutputRedactor.mask))
    }

    func testRedactsJwtShapes() {
        let output = OutputRedactor.redact("jwt=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVNHj0")
        XCTAssertFalse(output.contains("eyJhbGciOiJIUzI1NiJ9"))
        XCTAssertTrue(output.contains(OutputRedactor.mask))
    }

    func testKeepsOrdinaryBuildOutput() {
        // 普通构建/测试输出必须原样通过——脱敏不能破坏可用性。
        let ordinary = """
        Test Suite 'All tests' passed at 2026-09-09.
        Executed 19 tests, with 0 failures (0 unexpected)
        Build complete! (2.34s)
        /Users/dev/Projects/TermiPad: ok
        """
        XCTAssertEqual(OutputRedactor.redact(ordinary), ordinary)
    }

    func testKeepsShortHexAndVersionNumbers() {
        // 短 hex（< 20 位）不是 AWS Key；版本号/时间戳不受影响。
        let ordinary = "commit 0cdbc90 passed at 20:17:37, version 1.102.2"
        XCTAssertEqual(OutputRedactor.redact(ordinary), ordinary)
    }
}
