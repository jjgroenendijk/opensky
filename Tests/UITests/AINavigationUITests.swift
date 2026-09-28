// World > AI & Navigation UI surface (issue #203, roadmap item 16.8), in its own
// case rather than in `OpenSkyUITests` for the strict-lint type-length cap.
//
// The id contract is pinned in `DestinationRegistryTests` and
// `M16AcceptancePanelTests` as well; only a UI test proves the ids are reachable
// in the built view hierarchy, which is the gap issue #380 recorded.

import XCTest

final class AINavigationUITests: OpenSkyUITestCase {
    /// World > AI & Navigation acceptance surface (M16, issue #203): the sidebar
    /// lists the destination the milestone gate names, and selecting it exposes
    /// every control the gate drives together with the seven readouts they
    /// change.
    @MainActor
    func testAINavigationControlsAndReadouts() throws {
        let app = try launchApp()
        selectDestination("Destination-aiNavigation", in: app)

        XCTAssertTrue(
            app.checkBoxes["AINavmeshOverlayControl"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.checkBoxes["AIPathOverlayControl"].exists)
        XCTAssertTrue(app.checkBoxes["AIDetectionOverlayControl"].exists)
        XCTAssertTrue(app.popUpButtons["AIActorSelectControl"].exists)
        XCTAssertTrue(app.buttons["AIActorCrosshairControl"].exists)
        XCTAssertTrue(app.buttons["AIMoveToCrosshairControl"].exists)
        XCTAssertTrue(app.buttons["AIMoveStopControl"].exists)
        XCTAssertTrue(app.buttons["AIPackageReevaluateControl"].exists)
        XCTAssertTrue(app.checkBoxes["AIHostilityControl"].exists)

        for readout in [
            "AIOverlayStatsLabel", "AIActorStatsLabel", "AIMovementStatsLabel",
            "AIPackageStatsLabel", "DetectionStatsLabel", "DetectionSettingsStatsLabel",
            "AICombatStatsLabel"
        ] {
            XCTAssertTrue(app.staticTexts[readout].exists, readout)
        }
    }
}
