import XCTest
import SwiftData
@testable import TermiPad

/// M0 mobile entry data model + revocation behavior tests (track-protocol stage 4.3).
///
/// Corresponds to row 1 of the completion bar in docs/m0-m1-mobile-entry-design.md §2.7, "6 fields persisted +
/// default false/nil/everyTime".
final class MobileEntryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var tool: TerminalTool!

    override func setUpWithError() throws {
        continueAfterFailure = false
        container = try TermiPadDataStore.makeContainer(isStoredInMemoryOnly: true)
        context = ModelContext(container)
        tool = TerminalTool(
            name: "merge-cli",
            executablePath: "/usr/local/bin/merge-cli",
            commandTemplate: "merge-cli"
        )
    }

    override func tearDownWithError() throws {
        // an in-memory container can simply be discarded
    }

    func testDefaultsAreAllClosed() {
        // docs/m0-m1-mobile-entry-design.md §2.2: "all off by default"
        XCTAssertNil(tool.mobileDisplayName, "mobileDisplayName defaults to nil (uses the local name).")
        XCTAssertEqual(tool.mobileDescription, "", "mobileDescription defaults to an empty string.")
        XCTAssertFalse(tool.showInMobileEntry, "showInMobileEntry defaults to false.")
        XCTAssertFalse(tool.allowMobileLaunchRequest, "allowMobileLaunchRequest defaults to false.")
        XCTAssertEqual(tool.mobileLocalConfirmPolicy, .everyTime, "mobileLocalConfirmPolicy defaults to .everyTime.")
        XCTAssertNil(tool.revokeMobilePermissionAt, "revokeMobilePermissionAt defaults to nil.")
    }

    func testRoundTripPersistsAllSixFields() throws {
        tool.mobileDisplayName = "Project Sync"
        tool.mobileDescription = "Run git pull --rebase"
        tool.showInMobileEntry = true
        tool.allowMobileLaunchRequest = true
        tool.mobileLocalConfirmPolicy = .perSession
        tool.revokeMobilePermissionAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(tool)
        try context.save()

        let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<TerminalTool>()).first)
        XCTAssertEqual(fetched.mobileDisplayName, "Project Sync")
        XCTAssertEqual(fetched.mobileDescription, "Run git pull --rebase")
        XCTAssertTrue(fetched.showInMobileEntry)
        XCTAssertTrue(fetched.allowMobileLaunchRequest)
        XCTAssertEqual(fetched.mobileLocalConfirmPolicy, .perSession)
        XCTAssertEqual(fetched.revokeMobilePermissionAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testRevokeTripleActionSetsAllThreeFields() throws {
        // docs/m0-m1-mobile-entry-design.md §2.4: "revocation = write the timestamp + turn off the 2 switches"
        // Here we mutate + save directly to simulate the side effects of performMobileRevoke() (the button itself is covered by UI tests).
        tool.showInMobileEntry = true
        tool.allowMobileLaunchRequest = true
        tool.mobileLocalConfirmPolicy = .lowRiskSessionOnly
        context.insert(tool)
        try context.save()

        // Simulate performMobileRevoke's double revocation
        tool.revokeMobilePermissionAt = Date()
        tool.showInMobileEntry = false
        tool.allowMobileLaunchRequest = false
        try context.save()

        let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<TerminalTool>()).first)
        XCTAssertNotNil(fetched.revokeMobilePermissionAt, "The timestamp is written after revocation.")
        XCTAssertFalse(fetched.showInMobileEntry, "showInMobileEntry is turned off after revocation.")
        XCTAssertFalse(fetched.allowMobileLaunchRequest, "allowMobileLaunchRequest is turned off after revocation.")
        // mobileLocalConfirmPolicy is outside the scope of revocation — the user's preference is kept so it can be reused when turned on again later.
        XCTAssertEqual(fetched.mobileLocalConfirmPolicy, .lowRiskSessionOnly,
                       "Revocation does not affect the confirm policy — the user's preference is kept.")
    }

    func testAllThreePolicyCasesRoundTrip() throws {
        for policy: MobileLocalConfirmPolicy in [.everyTime, .perSession, .lowRiskSessionOnly] {
            let localTool = TerminalTool(
                name: "policy-\(policy.rawValue)",
                executablePath: "/usr/local/bin/p",
                commandTemplate: "p"
            )
            localTool.mobileLocalConfirmPolicy = policy
            context.insert(localTool)
            try context.save()
        }
        let all = try context.fetch(FetchDescriptor<TerminalTool>())
        XCTAssertEqual(Set(all.map(\.mobileLocalConfirmPolicy)),
                       Set([.everyTime, .perSession, .lowRiskSessionOnly]))
    }

    func testMigrationFromOlderRecordWithoutMobileFields() throws {
        // Simulate a record from an old store without the 6 fields (forward compatibility: M0 is an overlay)
        // Adding Optional fields to a SwiftData @Model should not break loading old records.
        // Here we directly construct a TerminalTool whose 6 fields were never set, simulating old-record semantics.
        let old = TerminalTool(
            name: "legacy",
            executablePath: "/usr/local/bin/legacy",
            commandTemplate: "legacy"
        )
        // Do not set the 6 fields
        context.insert(old)
        try context.save()

        let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<TerminalTool>()).first(where: { $0.name == "legacy" }))
        XCTAssertNil(fetched.mobileDisplayName)
        XCTAssertEqual(fetched.mobileDescription, "")
        XCTAssertFalse(fetched.showInMobileEntry)
        XCTAssertFalse(fetched.allowMobileLaunchRequest)
        XCTAssertEqual(fetched.mobileLocalConfirmPolicy, .everyTime)
        XCTAssertNil(fetched.revokeMobilePermissionAt)
    }
}
