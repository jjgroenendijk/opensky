// Smoke tests: app launches, shows its main window, and every sidebar
// destination remains reachable. Real-data screenshots are env-gated; host
// copies runner temp output into gitignored logs/ for inspection.
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

    /// Launches against explicit external data. Caller gates the path; no
    /// default-root fallback keeps CI deterministic.
    @MainActor
    private func launchApp(dataRoot: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["OPENSKY_DATA_ROOT"] = dataRoot
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    func testAppLaunchesAndShowsWindow() throws {
        let app = try launchApp()
        XCTAssertEqual(app.dialogs.count, 0, "No game-data alert expected with valid root")
        XCTAssertTrue(app.outlines["AppSidebar"].waitForExistence(timeout: 5))
        // CI runners may expose AppKit accessibility without Metal 4.
        XCTAssertTrue(app.buttons["ScreenshotButton"].exists)
    }

    /// World > Environment sidebar surface (M7.1.2): the sidebar lists the
    /// Environment destination, selecting it exposes the sun-shadow quality
    /// control + live stats readout, particle controls, and only implemented LOD values.
    /// Runs on synthetic data; renderer falls back to DemoScene.
    @MainActor
    func testWorldSidebarEnvironmentShadowQuality() throws {
        let app = try launchApp()
        let sidebar = app.outlines["AppSidebar"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.cells["Destination-environment"].firstMatch.click()

        let quality = app.popUpButtons["ShadowQualityControl"]
        XCTAssertTrue(quality.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ShadowStatsLabel"].exists)
        XCTAssertTrue(app.checkBoxes["AnimationsEnabledControl"].exists)
        XCTAssertTrue(app.checkBoxes["WeatherEnabledControl"].exists)
        XCTAssertTrue(app.checkBoxes["ParticlesEnabledControl"].exists)
        XCTAssertTrue(app.checkBoxes["ParticlesFrozenControl"].exists)
        XCTAssertTrue(app.sliders["ParticleEmissionControl"].exists)
        XCTAssertTrue(app.checkBoxes["PrecipitationEnabledControl"].exists)
        XCTAssertTrue(app.checkBoxes["GrassEnabledControl"].exists)
        XCTAssertTrue(app.sliders["GrassDensityControl"].exists)
        XCTAssertTrue(app.sliders["GrassDistanceControl"].exists)
        XCTAssertTrue(app.sliders["GrassWindControl"].exists)
        XCTAssertTrue(app.buttons["ClearWeatherControl"].exists)
        XCTAssertTrue(app.buttons["RainWeatherControl"].exists)
        XCTAssertTrue(app.buttons["SnowWeatherControl"].exists)
        XCTAssertTrue(app.checkBoxes["WeatherTransitionsPausedControl"].exists)
        XCTAssertTrue(app.textFields["LODLevel0DistanceField"].exists)
        XCTAssertTrue(app.textFields["LODLevel1DistanceField"].exists)
        XCTAssertTrue(app.textFields["LODMaximumDistanceField"].exists)
        XCTAssertTrue(app.textFields["LODTreeDistanceField"].exists)
        XCTAssertTrue(app.buttons["LODApplyButton"].exists)
        XCTAssertTrue(app.buttons["LODResetButton"].exists)

        quality.click()
        app.menuItems["Low"].click()
        XCTAssertEqual(quality.value as? String, "Low")
    }

    /// Developer > UI Lab sidebar surface (M8.1.1 + M8.1.4): the sidebar lists
    /// the UI Lab destination; selecting it exposes the overlay-enable + sample
    /// toggles, the scale preset popup, the menu-mode preview buttons, and the
    /// live UIDrawStats / menu-stack / localized-strings readouts.
    @MainActor
    func testWorldSidebarUILabControls() throws {
        let app = try launchApp()
        let sidebar = app.outlines["AppSidebar"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.cells["Destination-uiLab"].firstMatch.click()

        XCTAssertTrue(app.checkBoxes["UIOverlayEnabledControl"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.checkBoxes["UILabSampleControl"].exists)
        XCTAssertTrue(app.checkBoxes["UIStringsSampleControl"].exists)
        XCTAssertTrue(app.popUpButtons["UIScaleControl"].exists)
        XCTAssertTrue(app.staticTexts["UIStatsLabel"].exists)
        XCTAssertTrue(app.buttons["UIMenuPushControl"].exists)
        XCTAssertTrue(app.buttons["UIMenuPopControl"].exists)
        XCTAssertTrue(app.buttons["UIMenuClearControl"].exists)
        XCTAssertTrue(app.staticTexts["UIMenuStatsLabel"].exists)
        XCTAssertTrue(app.staticTexts["UIStringsStatsLabel"].exists)

        // Menu-mode preview round trip: push pauses world sim, clear resumes.
        app.buttons["UIMenuPushControl"].click()
        let menuStats = app.staticTexts["UIMenuStatsLabel"]
        XCTAssertTrue(menuStats.label.contains("paused") || waitForPause(menuStats))
        app.buttons["UIMenuClearControl"].click()
    }

    /// The 2 Hz readout ticker may lag one interaction; poll briefly.
    @MainActor
    private func waitForPause(_ label: XCUIElement) -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if label.label.contains("paused") {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    /// Library > Asset Browser: a full-content destination covering the game
    /// view; the toolbar screenshot stays disabled while it is frontmost.
    @MainActor
    func testSidebarShowsAssetBrowser() throws {
        let app = try launchApp()
        let sidebar = app.outlines["AppSidebar"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.cells["Destination-assetBrowser"].firstMatch.click()
        XCTAssertTrue(app.popUpButtons["AssetCategory"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.searchFields["AssetFilter"].exists)
        XCTAssertTrue(app.tables["AssetTable"].exists)
        XCTAssertFalse(app.buttons["ScreenshotButton"].isEnabled)
    }

    @MainActor
    func testMissingDataStaysInWindowAndSettingsOpens() {
        let app = XCUIApplication()
        app.launchEnvironment["OPENSKY_DATA_ROOT"] = "/invalid/opensky-uitest-root"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.dialogs.count, 0)
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "value CONTAINS 'not a Skyrim SE install'")
            ).firstMatch.exists
        )

        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.windows["Settings"].waitForExistence(timeout: 5))
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

    /// Milestone 3.3 visual proof over user's read-only install. Set
    /// OPENSKY_DATA_ROOT for the UI-test runner; CI skips without it.
    @MainActor
    func testCapturesWorldAndAssetBrowserWithRealData() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let root = environment["OPENSKY_DATA_ROOT"], !root.isEmpty else {
            throw XCTSkip("OPENSKY_DATA_ROOT not set for UI-test runner")
        }
        let app = launchApp(dataRoot: root)
        let window = app.windows.firstMatch
        let worldFrame = window.frame

        Thread.sleep(forTimeInterval: 5)
        try write(window.screenshot(), name: "app-world.png")

        app.outlines["AppSidebar"].cells["Destination-assetBrowser"].firstMatch.click()
        let table = app.tables["AssetTable"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        XCTAssertTrue(table.tableRows.firstMatch.waitForExistence(timeout: 30))
        table.tableRows.firstMatch.click()
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(window.frame.width, worldFrame.width, accuracy: 1)
        XCTAssertEqual(window.frame.height, worldFrame.height, accuracy: 1)
        try write(window.screenshot(), name: "app-asset-browser.png")
    }

    private func write(_ screenshot: XCUIScreenshot, name: String) throws {
        // UI-test runner is containerized and cannot write into repo logs/.
        // Host verification copies these logged temp paths after the run.
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        try screenshot.pngRepresentation.write(to: url)
        NSLog("mode screenshot: \(url.path)")
        XCTAssertGreaterThan(screenshot.pngRepresentation.count, 0)
    }
}
