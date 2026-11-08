// Smoke tests: the app launches and shows the game window. OPENSKY_DATA_ROOT
// points at a synthetic install (an empty Skyrim.esm marker), so the data probe
// passes without the game.

import XCTest

final class OpenSkyUITests: OpenSkyUITestCase {
    @MainActor
    func testAppLaunchesAndShowsWindow() throws {
        let app = try launchApp()
        XCTAssertEqual(app.dialogs.count, 0, "No game-data alert expected with valid root")
        XCTAssertTrue(app.windows["OpenSky"].waitForExistence(timeout: 10))
    }

    /// Without an install a forced start stays on the launcher, and Settings opens there.
    @MainActor
    func testMissingDataStaysOnTheLauncherAndSettingsOpens() {
        let app = launchApp(dataRoot: "/invalid/opensky-uitest-root")
        XCTAssertEqual(app.dialogs.count, 0)
        XCTAssertTrue(app.buttons["LaunchPlayControl"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["LaunchPlayControl"].isEnabled)

        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.windows["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["SettingsLanguageControl"].exists)
        XCTAssertTrue(app.staticTexts["SettingsLanguageStatsLabel"].exists)
        XCTAssertTrue(app.buttons["SettingsApplyLanguageControl"].exists)
        XCTAssertTrue(app.buttons["SettingsResetLanguageControl"].exists)
    }

    /// Captures the rendered frame to a temp PNG and logs the path — the
    /// visual-verification hook for renderer work (Screen Recording TCC is
    /// unavailable on dev machines; XCUITest screenshots are not).
    @MainActor
    func testCapturesRenderedFrame() throws {
        let app = try launchApp()
        let window = app.windows.firstMatch
        // Kept: let the render loop present a few frames before capturing.
        Thread.sleep(forTimeInterval: 2)
        try write(window.screenshot(), name: "opensky-frame-\(UUID().uuidString).png")
    }

    /// A capture over the user's read-only install. Set OPENSKY_DATA_ROOT for
    /// the UI-test runner; CI skips without it.
    @MainActor
    func testCapturesTheWorldWithRealData() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let root = environment["OPENSKY_DATA_ROOT"], !root.isEmpty else {
            throw XCTSkip("OPENSKY_DATA_ROOT not set for UI-test runner")
        }
        let app = launchApp(dataRoot: root)
        // Kept: the capture needs streamed cells on screen, and no UI element
        // reports that.
        Thread.sleep(forTimeInterval: 5)
        try write(app.windows.firstMatch.screenshot(), name: "app-world.png")
    }

    @MainActor
    private func write(_ screenshot: XCUIScreenshot, name: String) throws {
        // UI-test runner is containerized and cannot write into repo .logs/.
        // Host verification copies these logged temp paths after the run.
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        try screenshot.pngRepresentation.write(to: url)
        NSLog("game screenshot: \(url.path)")
        XCTAssertGreaterThan(screenshot.pngRepresentation.count, 0)
    }
}
