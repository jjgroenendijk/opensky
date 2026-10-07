// Launch and navigation helpers for every UI-test case. A base class because
// both need `addTeardownBlock` and the case's `XCUIApplication`.

import XCTest

class OpenSkyUITestCase: XCTestCase {
    /// Launches the app against a synthetic data root; returns the running
    /// app with its window on screen. Developer mode unless the case asks for
    /// the launcher with an empty mode.
    @MainActor
    func launchApp(
        launchMode: String = "developer", environment: [String: String] = [:]
    ) throws -> XCUIApplication {
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
        app.launchEnvironment.merge(environment) { _, given in given }
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
        // A short window hides the lower rows, and a click there misses. XCUI
        // still calls such a row hittable, so compare frames instead.
        let window = app.windows.firstMatch
        for deltaY: CGFloat in [-200, 200] {
            for _ in 0 ..< 10 where !window.frame.contains(row.frame) {
                sidebar.scroll(byDeltaX: 0, deltaY: deltaY)
            }
        }
        row.click()
        expandCollapsedSections(in: app)
    }

    /// The app restores each section's collapse state from the user's saved
    /// preferences, so a test opens every section before it reads one. Bottom
    /// up, so opening one section does not move the ones still to open.
    @MainActor
    func expandCollapsedSections(in app: XCUIApplication) {
        let collapsed = app.disclosureTriangles.matching(
            NSPredicate(format: "identifier ENDSWITH '-Disclosure' AND value == 0")
        )
        // Read the ids once: a value read just after a click can be stale, and
        // a second click would close the section again.
        let ids = collapsed.allElementsBoundByIndex.map(\.identifier)
        for id in ids.reversed() {
            let disclosure = app.disclosureTriangles[id]
            let panel = app.scrollViews.containing(.disclosureTriangle, identifier: id).firstMatch
            // XCUI does not scroll a panel to reach a click target.
            for _ in 0 ..< 20 where !panel.frame.contains(disclosure.frame) {
                let below = disclosure.frame.minY > panel.frame.midY
                panel.scroll(byDeltaX: 0, deltaY: below ? -200 : 200)
            }
            disclosure.click()
        }
        XCTAssertTrue(collapsed.firstMatch.waitForNonExistence(timeout: 5))
    }
}
