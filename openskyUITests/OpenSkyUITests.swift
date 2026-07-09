// Smoke test: app launches and shows its main window.

import XCTest

final class OpenSkyUITests: XCTestCase {
    @MainActor
    func testAppLaunchesAndShowsWindow() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }
}
