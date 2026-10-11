import XCTest
@testable import TermiPad

/// ControlledInstallPlan contract tests (track-protocol stage 8 test hardening 1/4).
///
/// Locks down the install plan lookup contract + the formula regex + the 13 entries of the reviewed plans table.
/// No network writes / no Process calls / no writes to ~ — all contract-style, stable in CI.
final class ControlledInstallPlanContractTests: XCTestCase {
    // MARK: - isValidFormula regex lock

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
        XCTAssertFalse(ControlledInstallCatalog.isValidFormula("GH"))  // uppercase first letter is rejected
        // "1gh" is actually accepted (a digit followed by letters) — that is how the regex is designed; test the boundaries: empty string and whitespace
        XCTAssertFalse(ControlledInstallCatalog.isValidFormula(""))
        XCTAssertFalse(ControlledInstallCatalog.isValidFormula(" "))
    }

    // MARK: - reviewedPlans 13 entry contract

    func testReviewedPlansReturnsThirteenEntries() {
        // The 13 formulae are the concrete list behind the verify-macos.sh:97-100 guard "there must be a brew install (formula) template"
        // Adding an entry requires 1 new commit + a guard
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
        // auditDate has the form YYYY-MM-DD, catalogRevision the form YYYY.MM.DD.N
        let datePattern = #"^\d{4}-\d{2}-\d{2}$"#
        let revPattern = #"^\d{4}\.\d{2}\.\d{2}\.\d+$"#
        for plan in ControlledInstallCatalog.reviewedPlans {
            XCTAssertTrue(plan.auditedAt.range(of: datePattern, options: .regularExpression) != nil,
                          "\(plan.toolName).auditedAt has a bad format: \(plan.auditedAt)")
            XCTAssertTrue(plan.catalogRevision.range(of: revPattern, options: .regularExpression) != nil,
                          "\(plan.toolName).catalogRevision has a bad format: \(plan.catalogRevision)")
        }
    }

    // MARK: - plan lookup behavior

    func testPlanByRepositoryFullNameIsCaseInsensitive() {
        // sxyazi/yazi is in the source — lookup should match it (case-insensitive comparison)
        let plan = ControlledInstallCatalog.plan(forRepositoryFullName: "SXYazi/Yazi")
        XCTAssertNotNil(plan, "case-insensitive lookup failed — guard this contract so matching does not die")
        XCTAssertEqual(plan?.toolName, "yazi")
    }

    func testPlanByRepositoryFullNameFailsForUnknownName() {
        XCTAssertNil(ControlledInstallCatalog.plan(forRepositoryFullName: "cli/cli-fork"))
        XCTAssertNil(ControlledInstallCatalog.plan(forRepositoryFullName: ""))
        XCTAssertNil(ControlledInstallCatalog.plan(forRepositoryFullName: "x/y"))
    }

    func testPlanByFormulaIsCaseInsensitiveAndSkipsInvalid() {
        // lookup skips inputs with isValidFormula=false (prevents injecting "gh;evil" via lookup)
        let gh = ControlledInstallCatalog.plan(forFormula: "GH")
        XCTAssertNotNil(gh, "case-insensitive lookup")
        let bad = ControlledInstallCatalog.plan(forFormula: "gh;rm -rf /")
        XCTAssertNil(bad, "a malicious formula should be skipped")
    }

    // MARK: - safety properties (project red lines)

    func testSafetyBoundariesAreAlwaysTrue() {
        // verify-macos.sh:111-113 requires these constants to stay true — any commit changing them to false is caught by the guard immediately
        XCTAssertTrue(ControlledInstallBoundary.doesNotRunInApp)
        XCTAssertTrue(ControlledInstallBoundary.doesNotAutoCollectResult)
        XCTAssertTrue(ControlledInstallBoundary.doesNotUseRemoteCommands)
        XCTAssertTrue(ControlledInstallBoundary.doesNotSupportThirdPartyTaps)
    }

    // MARK: - displayName & safetySummary in both languages

}
