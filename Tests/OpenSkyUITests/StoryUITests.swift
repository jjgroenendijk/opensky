// World > Quests & Journal > Scenes and Story Manager, and World > Dialogue &
// Voice > Dialogue Branches UI test. Unit tests pin the ids; only a UI test
// proves the surfaces are reachable.

import XCTest

final class StoryUITests: OpenSkyUITestCase {
    @MainActor
    func testSceneAndStoryControlsAreReachable() throws {
        let app = try launchApp()
        selectDestination("Destination-journal", in: app)
        XCTAssertTrue(app.comboBoxes["ScenesSceneControl"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ScenesStartControl"].exists)
        XCTAssertTrue(app.buttons["ScenesStopControl"].exists)
        XCTAssertTrue(app.staticTexts["ScenesListStatsLabel"].exists)
        XCTAssertTrue(app.popUpButtons["StoryEventControl"].exists)
        XCTAssertTrue(app.buttons["StoryFireControl"].exists)
        XCTAssertTrue(app.staticTexts["StoryManagerStatsLabel"].exists)
    }

    @MainActor
    func testDialogueBranchControlsAreReachable() throws {
        let app = try launchApp()
        selectDestination("Destination-dialogueVoice", in: app)
        XCTAssertTrue(app.textFields["DialogueBranchFilterControl"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["DialogueBranchListStatsLabel"].exists)
        XCTAssertTrue(app.staticTexts["DialogueBranchStatsLabel"].exists)
    }
}
