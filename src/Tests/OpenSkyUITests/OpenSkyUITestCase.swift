// Launch helpers for every UI-test case. A base class because
// both need `addTeardownBlock` and the case's `XCUIApplication`.

import XCTest

class OpenSkyUITestCase: XCTestCase {
    /// Launches the app against a synthetic data root; returns the running
    /// app with its window on screen. The game window unless the case asks
    /// for the launcher.
    @MainActor
    func launchApp(
        skipsLauncher: Bool = true, environment: [String: String] = [:]
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
        app.launchEnvironment["OPENSKY_SKIP_LAUNCHER"] = skipsLauncher ? "1" : "0"
        // Keeps the socket of a game the user has open free.
        app.launchEnvironment["OPENSKY_AGENT_CONTROL"] = "0"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        return app
    }

    /// Launches against explicit external data. Caller gates the path; no
    /// default-root fallback keeps CI deterministic.
    @MainActor
    func launchApp(dataRoot: String, skipsLauncher: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["OPENSKY_DATA_ROOT"] = dataRoot
        app.launchEnvironment["OPENSKY_SKIP_LAUNCHER"] = skipsLauncher ? "1" : "0"
        // Keeps the socket of a game the user has open free.
        app.launchEnvironment["OPENSKY_AGENT_CONTROL"] = "0"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        return app
    }
}
