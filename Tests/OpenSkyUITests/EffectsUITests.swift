// World > Effects and World > Audio > Reverb UI test. Unit tests pin the ids;
// only a UI test proves the surfaces are reachable.

import XCTest

final class EffectsUITests: OpenSkyUITestCase {
    @MainActor
    func testEffectsControlsAreReachable() throws {
        let app = try launchApp()
        selectDestination("Destination-effects", in: app)
        XCTAssertTrue(app.checkBoxes["ImageSpacePassControl"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.popUpButtons["ImageSpaceForcedControl"].exists)
        XCTAssertTrue(app.popUpButtons["ImageSpaceModifierControl"].exists)
        XCTAssertTrue(app.sliders["ImageSpaceStrengthControl"].exists)
        XCTAssertTrue(app.buttons["ImageSpacePlayControl"].exists)
        XCTAssertTrue(app.comboBoxes["VisualEffectNameControl"].exists)
        XCTAssertTrue(app.buttons["VisualEffectAttachPlayerControl"].exists)
        XCTAssertTrue(app.popUpButtons["ExplosionSelectControl"].exists)
        XCTAssertTrue(app.buttons["ExplosionDetonateControl"].exists)
        XCTAssertTrue(app.buttons["HazardSpawnControl"].exists)
        XCTAssertTrue(app.staticTexts["ExplosionStatsLabel"].exists)
    }

    @MainActor
    func testReverbControlsAreReachable() throws {
        let app = try launchApp()
        selectDestination("Destination-audio", in: app)
        XCTAssertTrue(app.checkBoxes["AudioReverbOverrideControl"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["AudioReverbWetLevelControl"].exists)
        XCTAssertTrue(app.staticTexts["AudioReverbStatsLabel"].exists)
    }
}
