// The launch and navigation helpers every UI-test case shares (issue #198 split
// them out of `OpenSkyUITests` for the strict-lint type-length cap).
//
// A base class rather than a free function pair, because both helpers need
// `addTeardownBlock` and the `XCUIApplication` lifetime the case owns.

import XCTest

class OpenSkyUITestCase: XCTestCase {
    /// Launches the app against a synthetic data root; returns the running
    /// app with its window on screen.
    @MainActor
    func launchApp() throws -> XCUIApplication {
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
    func launchApp(dataRoot: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["OPENSKY_DATA_ROOT"] = dataRoot
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        return app
    }

    /// Selects a sidebar destination by its registered accessibility id.
    ///
    /// The rows are `NSTableCellView`s, which AppKit publishes to the
    /// accessibility hierarchy as groups rather than `AXCell`s, so
    /// `outlines["AppSidebar"].cells[...]` never matches one however correct the
    /// identifier is. Matching on the identifier alone is what actually reaches
    /// the row, and is the assertion `DestinationRegistryTests` cannot make: it
    /// pins the id string, not its reachability in the built hierarchy.
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
