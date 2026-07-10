// Smoke tests: app launches, shows its main window, and renders frames.
//
// Launches with OPENSKY_DATA_ROOT pointing at a synthetic install (empty
// Skyrim.esm marker) so the game-data probe succeeds deterministically on
// machines without the game — no alert, no dependency on real data.

import XCTest

final class OpenSkyUITests: XCTestCase {
    /// Launches the app against a synthetic data root; returns the running
    /// app with its window on screen.
    @MainActor
    private func launchApp() throws -> XCUIApplication {
        let install = FileManager.default.temporaryDirectory
            .appending(path: "opensky-uitest-\(UUID().uuidString)")
        let data = install.appending(path: "Data")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: data.appending(path: "Skyrim.esm").path,
            contents: nil
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: install) }

        let app = XCUIApplication()
        app.launchEnvironment["OPENSKY_DATA_ROOT"] = install.path(percentEncoded: false)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    func testAppLaunchesAndShowsWindow() throws {
        let app = try launchApp()
        XCTAssertEqual(app.dialogs.count, 0, "No game-data alert expected with valid root")
    }

    /// Captures the rendered frame to a temp PNG and logs the path — the
    /// visual-verification hook for renderer work (Screen Recording TCC is
    /// unavailable on dev machines; XCUITest screenshots are not).
    @MainActor
    func testCapturesRenderedFrame() throws {
        let app = try launchApp()
        let window = app.windows.firstMatch
        // Let the render loop present a few frames before capturing.
        Thread.sleep(forTimeInterval: 2)
        let screenshot = window.screenshot()
        let url = FileManager.default.temporaryDirectory
            .appending(path: "opensky-frame-\(UUID().uuidString).png")
        try screenshot.pngRepresentation.write(to: url)
        NSLog("rendered frame screenshot: \(url.path)")
        XCTAssertGreaterThan(screenshot.pngRepresentation.count, 0)
    }
}
