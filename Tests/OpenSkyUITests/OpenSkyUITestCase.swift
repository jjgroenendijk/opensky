// Launch and navigation helpers for every UI-test case. A base class because
// both need `addTeardownBlock` and the case's `XCUIApplication`.

import XCTest

class OpenSkyUITestCase: XCTestCase {
    /// Launches the app against a synthetic data root; returns the running
    /// app with its window on screen. Developer mode unless the case asks for
    /// the launcher with an empty mode.
    @MainActor
    func launchApp(launchMode: String = "developer") throws -> XCUIApplication {
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
        app.launchEnvironment["OPENSKY_LAUNCH_MODE"] = launchMode
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        return app
    }

    /// Launches against explicit external data. Caller gates the path; no
    /// default-root fallback keeps CI deterministic.
    @MainActor
    func launchApp(dataRoot: String, launchMode: String = "developer") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["OPENSKY_DATA_ROOT"] = dataRoot
        app.launchEnvironment["OPENSKY_LAUNCH_MODE"] = launchMode
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        return app
    }

    /// Selects a sidebar destination by accessibility id. AppKit publishes the
    /// `NSTableCellView` rows as groups, not `AXCell`s, so
    /// `outlines["AppSidebar"].cells[...]` never matches; the id alone does.
    @MainActor
    func selectDestination(_ identifier: String, in app: XCUIApplication) {
        let sidebar = app.outlines["AppSidebar"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        let row = sidebar.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 5),
            "sidebar row \(identifier) is registered but not reachable"
        )
        row.click()
    }
}
