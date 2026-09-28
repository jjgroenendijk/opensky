// World > Render Debug UI surface (issue #144), in its own case rather than in
// `OpenSkyUITests` for the strict-lint type-length cap.
//
// The id contract is pinned in `RenderDebugSectionTests` too; only a UI test
// proves the ids are reachable in the built view hierarchy, which is the gap
// issue #380 recorded.

import XCTest

final class RenderDebugUITests: OpenSkyUITestCase {
    /// Selecting the launch destination exposes the debug channel selector, the
    /// isolation selector, every per-layer checkbox and the section readout.
    @MainActor
    func testRenderDebugControlsAndReadout() throws {
        let app = try launchApp()
        selectDestination("Destination-world", in: app)

        XCTAssertTrue(
            app.popUpButtons["RenderDebugModeControl"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.popUpButtons["RenderDebugSoloControl"].exists)
        for layer in [
            "Statics", "Actors", "DistantLOD", "Terrain", "Grass", "Water", "Sky", "Particles"
        ] {
            let identifier = "RenderDebugLayer\(layer)Control"
            XCTAssertTrue(app.checkBoxes[identifier].exists, identifier)
        }
        XCTAssertTrue(app.staticTexts["RenderDebugStatsLabel"].exists)
    }
}
