// World > Crime & Factions UI surface (issue #507, roadmap item 21.8), in its
// own case rather than in `OpenSkyUITests` for the strict-lint type-length cap.
//
// The id contract is pinned in `CrimeFactionPanelTests` too; only a UI test
// proves the ids are reachable in the built view hierarchy, which is the gap
// issue #380 recorded.

import XCTest

final class CrimeFactionsUITests: OpenSkyUITestCase {
    /// Selecting the crime destination exposes the bounty, membership and
    /// vendor controls and every section readout — with the bounty readout the
    /// milestone's acceptance record names.
    @MainActor
    func testCrimeFactionControlsAndBountyReadout() throws {
        let app = try launchApp()
        selectDestination("Destination-crimeFactions", in: app)

        XCTAssertTrue(app.buttons["CrimeBountyAddControl"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.popUpButtons["CrimeBountyFactionControl"].exists)
        XCTAssertTrue(app.textFields["CrimeBountyAmountControl"].exists)
        XCTAssertTrue(app.checkBoxes["CrimeBountyViolentControl"].exists)
        XCTAssertTrue(app.buttons["CrimeBountyClearControl"].exists)
        XCTAssertTrue(app.buttons["CrimeGuardCheckControl"].exists)
        XCTAssertTrue(app.buttons["CrimeResistArrestControl"].exists)

        XCTAssertTrue(app.buttons["FactionSubjectCrosshairControl"].exists)
        XCTAssertTrue(app.buttons["FactionSubjectPlayerControl"].exists)
        XCTAssertTrue(app.popUpButtons["FactionSelectControl"].exists)
        XCTAssertTrue(app.textFields["FactionRankControl"].exists)
        XCTAssertTrue(app.buttons["FactionJoinControl"].exists)
        XCTAssertTrue(app.buttons["FactionLeaveControl"].exists)
        XCTAssertTrue(app.popUpButtons["FactionVendorOverrideControl"].exists)
        XCTAssertTrue(app.buttons["FactionBarterControl"].exists)

        // The bounty readout: what the milestone acceptance record points at.
        let bounty = app.staticTexts["CrimeBountyStatsLabel"]
        XCTAssertTrue(bounty.exists)
        XCTAssertTrue(app.staticTexts["CrimeTheftStatsLabel"].exists)
        XCTAssertTrue(app.staticTexts["FactionMembershipStatsLabel"].exists)
        XCTAssertTrue(app.staticTexts["FactionVendorStatsLabel"].exists)
        // A launch with no game data reports the absence rather than a zero.
        let text = bounty.value as? String ?? ""
        XCTAssertTrue(
            text.contains("Bounty:") || text.contains("unavailable"),
            "bounty readout said: \(text)"
        )
    }
}
