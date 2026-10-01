// World > Render Debug UI test, its own case for the type-length cap. Unit
// tests pin the ids; only a UI test proves they are reachable.

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
