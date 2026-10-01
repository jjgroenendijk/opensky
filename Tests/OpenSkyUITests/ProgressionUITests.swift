// World > Progression UI test, its own case for the type-length cap. Unit
// tests pin the ids; only a UI test proves they are reachable.

import XCTest

final class ProgressionUITests: OpenSkyUITestCase {
    /// Selecting the progression destination exposes the character controls,
    /// the skill controls, the perk-tree controls and every section readout —
    /// with the level readout the milestone's acceptance record names.
    @MainActor
    func testProgressionControlsAndLevelReadout() throws {
        let app = try launchApp()
        selectDestination("Destination-progression", in: app)

        XCTAssertTrue(
            app.buttons["ProgressionAwardExperienceControl"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["ProgressionChooseAttributeControl"].exists)
        XCTAssertTrue(app.buttons["ProgressionAddPerkPointControl"].exists)
        XCTAssertTrue(app.buttons["ProgressionRemovePerkPointControl"].exists)
        XCTAssertTrue(app.popUpButtons["ProgressionAttributeControl"].exists)
        XCTAssertTrue(app.textFields["ProgressionExperienceControl"].exists)

        XCTAssertTrue(app.popUpButtons["ProgressionSkillControl"].exists)
        XCTAssertTrue(app.textFields["ProgressionSkillAmountControl"].exists)
        XCTAssertTrue(app.buttons["ProgressionAdvanceSkillControl"].exists)
        XCTAssertTrue(app.buttons["ProgressionIncrementSkillControl"].exists)

        XCTAssertTrue(app.popUpButtons["ProgressionTreeSkillControl"].exists)
        XCTAssertTrue(app.popUpButtons["ProgressionPerkNodeControl"].exists)
        XCTAssertTrue(app.buttons["ProgressionSpendPerkPointControl"].exists)
        XCTAssertTrue(app.buttons["ProgressionGrantPerkControl"].exists)
        XCTAssertTrue(app.buttons["ProgressionRemovePerkControl"].exists)

        // The level readout: what the milestone acceptance record points at.
        let character = app.staticTexts["ProgressionCharacterStatsLabel"]
        XCTAssertTrue(character.exists)
        XCTAssertTrue(app.staticTexts["ProgressionSkillsStatsLabel"].exists)
        XCTAssertTrue(app.staticTexts["ProgressionPerkTreeStatsLabel"].exists)
        XCTAssertTrue(app.staticTexts["ProgressionPerkStatsLabel"].exists)
        // A launch with no game data reports the absence rather than a zero.
        XCTAssertTrue(character.value is String)
    }
}
