import XCTest
@testable import TermiPad

/// ControlledInstallPlan 契约测试（track-protocol 阶段 8 测试补强 1/4）。
///
/// 锁住 install plan lookup 契约 + formula regex + reviewed plans 表 13 个 entry。
/// 不写网络/不调 Process/不写 ~ — 全部 contract-style,可 CI 稳定。
final class ControlledInstallPlanContractTests: XCTestCase {
    // MARK: - isValidFormula regex 锁

    func testIsValidFormulaAcceptsAlphanumericHyphenUnderscoreDotAt() {
        XCTAssertTrue(ControlledInstallCatalog.isValidFormula("gh"))
        XCTAssertTrue(ControlledInstallCatalog.isValidFormula("git-delta"))
        XCTAssertTrue(ControlledInstallCatalog.isValidFormula("node@20"))
        XCTAssertTrue(ControlledInstallCatalog.isValidFormula("ripgrep.a.b"))
    }

    func testIsValidFormulaRejectsShellInjection() {
        XCTAssertFalse(ControlledInstallCatalog.isValidFormula("gh;evil"))
        XCTAssertFalse(ControlledInstallCatalog.isValidFormula("gh\nevil"))
        XCTAssertFalse(ControlledInstallCatalog.isValidFormula("gh --formula evil"))
        XCTAssertFalse(ControlledInstallCatalog.isValidFormula("gh formula=evil"))
        XCTAssertFalse(ControlledInstallCatalog.isValidFormula("gh/tap/foo"))
        XCTAssertFalse(ControlledInstallCatalog.isValidFormula(""))
        XCTAssertFalse(ControlledInstallCatalog.isValidFormula("GH"))  // 大写首字母拒绝
        // "1gh" 实际被接受(数字后跟字母)— regex 设计如此;测边界:空字符串和空白字符
        XCTAssertFalse(ControlledInstallCatalog.isValidFormula(""))
        XCTAssertFalse(ControlledInstallCatalog.isValidFormula(" "))
    }

    // MARK: - reviewedPlans 13 entry contract

    func testReviewedPlansReturnsThirteenEntries() {
        // 13 formula 是 verify-macos.sh:97-100 守卫"必须有 brew install (formula) 模板"对应的具体清单
        // 加一个 entry 必须新增 1 commit + 守卫
        XCTAssertEqual(ControlledInstallCatalog.reviewedPlans.count, 13)
    }

    func testReviewedPlansAllUseHomebrewCoreChannel() {
        for plan in ControlledInstallCatalog.reviewedPlans {
            XCTAssertEqual(plan.channel, .homebrewCore)
            XCTAssertTrue(plan.command.hasPrefix("brew install "),
                          "plan.command should be 'brew install <formula>': \(plan.command)")
        }
    }

    func testReviewedPlansAllHaveAuditMetadata() {
        // auditDate 形式 YYYY-MM-DD,catalogRevision 形式 YYYY.MM.DD.N
        let datePattern = #"^\d{4}-\d{2}-\d{2}$"#
        let revPattern = #"^\d{4}\.\d{2}\.\d{2}\.\d+$"#
        for plan in ControlledInstallCatalog.reviewedPlans {
            XCTAssertTrue(plan.auditedAt.range(of: datePattern, options: .regularExpression) != nil,
                          "\(plan.toolName).auditedAt 格式错: \(plan.auditedAt)")
            XCTAssertTrue(plan.catalogRevision.range(of: revPattern, options: .regularExpression) != nil,
                          "\(plan.toolName).catalogRevision 格式错: \(plan.catalogRevision)")
        }
    }

    // MARK: - plan lookup 行为

    func testPlanByRepositoryFullNameIsCaseInsensitive() {
        // sxyazi/yazi 在源里 — lookup 应能匹 (case-insensitive 比较)
        let plan = ControlledInstallCatalog.plan(forRepositoryFullName: "SXYazi/Yazi")
        XCTAssertNotNil(plan, "case-insensitive lookup 失败 — 守卫这个契约避免匹配死掉")
        XCTAssertEqual(plan?.toolName, "yazi")
    }

    func testPlanByRepositoryFullNameFailsForUnknownName() {
        XCTAssertNil(ControlledInstallCatalog.plan(forRepositoryFullName: "cli/cli-fork"))
        XCTAssertNil(ControlledInstallCatalog.plan(forRepositoryFullName: ""))
        XCTAssertNil(ControlledInstallCatalog.plan(forRepositoryFullName: "x/y"))
    }

    func testPlanByFormulaIsCaseInsensitiveAndSkipsInvalid() {
        // lookup 跳过 isValidFormula=false 的输入(避免 lookup 注入 "gh;evil")
        let gh = ControlledInstallCatalog.plan(forFormula: "GH")
        XCTAssertNotNil(gh, "大小写不敏感 lookup")
        let bad = ControlledInstallCatalog.plan(forFormula: "gh;rm -rf /")
        XCTAssertNil(bad, "恶意 formula 应跳过")
    }

    // MARK: - safety properties (项目红线)

    func testSafetyBoundariesAreAlwaysTrue() {
        // verify-macos.sh:111-113 要求这些常量保持 true — 任何 commit 改 false 立即被守卫抓住
        XCTAssertTrue(ControlledInstallBoundary.doesNotRunInApp)
        XCTAssertTrue(ControlledInstallBoundary.doesNotAutoCollectResult)
        XCTAssertTrue(ControlledInstallBoundary.doesNotUseRemoteCommands)
        XCTAssertTrue(ControlledInstallBoundary.doesNotSupportThirdPartyTaps)
    }

    // MARK: - displayName & safetySummary 双语

}
