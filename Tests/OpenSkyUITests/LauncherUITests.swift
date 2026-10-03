// The launcher: the app opens on it, shows the game folder, and each launch
// mode button opens its window.

import XCTest

final class LauncherUITests: OpenSkyUITestCase {
    @MainActor
    func testLauncherOpensDeveloperModeAndReturns() throws {
        let app = try launchApp(launchMode: "")
        XCTAssertTrue(app.tables["LauncherSidebar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["LauncherGameFolderStatsLabel"].exists)
        XCTAssertTrue(app.buttons["LauncherChooseGameFolderControl"].exists)
        XCTAssertTrue(app.buttons["LaunchPlayControl"].isEnabled)

        app.buttons["LaunchDeveloperControl"].click()
        XCTAssertTrue(app.outlines["AppSidebar"].waitForExistence(timeout: 10))

        app.typeKey("l", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["LaunchPlayControl"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.outlines["AppSidebar"].exists)
    }

    @MainActor
    func testPlayNeedsAGameFolder() {
        let app = launchApp(dataRoot: "/invalid/opensky-uitest-root", launchMode: "")
        XCTAssertTrue(app.buttons["LaunchPlayControl"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["LaunchPlayControl"].isEnabled)
        XCTAssertTrue(app.buttons["LaunchDeveloperControl"].isEnabled)
    }
}
