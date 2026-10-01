// World > AI & Navigation UI test, its own case for the type-length cap. Unit
// tests pin the ids; only a UI test proves they are reachable.

import XCTest

final class AINavigationUITests: OpenSkyUITestCase {
    /// The sidebar lists World > AI & Navigation, and selecting it shows every
    /// gate control and the seven readouts they change.
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
