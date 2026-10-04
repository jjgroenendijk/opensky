// World > Character, World > Map, and the System Menu page section. Unit tests
// pin the ids; only a UI test proves the controls are reachable.

import XCTest

final class MenusUITests: OpenSkyUITestCase {
    @MainActor
    func testCharacterMenuControlsAreReachable() throws {
        let app = try launchApp()
        selectDestination("Destination-characterMenus", in: app)
        XCTAssertTrue(app.buttons["TitleMenuOpenControl"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["TitleMenuChooseControl"].exists)
        XCTAssertTrue(app.staticTexts["TitleMenuStatsLabel"].exists)
        XCTAssertTrue(app.buttons["RaceMenuOpenControl"].exists)
        XCTAssertTrue(app.buttons["RaceMenuResetControl"].exists)
        XCTAssertTrue(app.buttons["RaceMenuDoneControl"].exists)
        XCTAssertTrue(app.textFields["RaceMenuNameControl"].exists)
        XCTAssertTrue(app.staticTexts["RaceMenuStatsLabel"].exists)
    }

    @MainActor
    func testMapMenuControlsAreReachable() throws {
        let app = try launchApp()
        selectDestination("Destination-mapMenu", in: app)
        XCTAssertTrue(app.buttons["MapMenuOpenWorldControl"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["MapMenuOpenLocalControl"].exists)
        XCTAssertTrue(app.buttons["MapMenuTravelControl"].exists)
        XCTAssertTrue(app.buttons["MapMenuRevealAllControl"].exists)
        XCTAssertTrue(app.buttons["MapMenuResetFogControl"].exists)
        XCTAssertTrue(app.staticTexts["MapMenuStatsLabel"].exists)
    }

    @MainActor
    func testSystemMenuPageControlsAreReachable() throws {
        let app = try launchApp()
        selectDestination("Destination-systemMenu", in: app)
        XCTAssertTrue(app.buttons["SystemMenuPageLeftControl"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["SystemMenuPageRightControl"].exists)
        XCTAssertTrue(app.buttons["SystemMenuPageBackControl"].exists)
        XCTAssertTrue(app.buttons["SystemMenuDeleteSaveControl"].exists)
        XCTAssertTrue(app.staticTexts["SystemMenuPageStatsLabel"].exists)
    }
}
