// Smoke test: app launches and shows its main window.
//
// Launches with OPENSKY_DATA_ROOT pointing at a synthetic install (empty
// Skyrim.esm marker) so the game-data probe succeeds deterministically on
// machines without the game — no alert, no dependency on real data.

import XCTest

final class OpenSkyUITests: XCTestCase {
    @MainActor
    func testAppLaunchesAndShowsWindow() throws {
        let install = FileManager.default.temporaryDirectory
            .appending(path: "opensky-uitest-\(UUID().uuidString)")
        let data = install.appending(path: "Data")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: data.appending(path: "Skyrim.esm").path,
            contents: nil
        )
        defer { try? FileManager.default.removeItem(at: install) }

        let app = XCUIApplication()
        app.launchEnvironment["OPENSKY_DATA_ROOT"] = install.path(percentEncoded: false)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.dialogs.count, 0, "No game-data alert expected with valid root")
    }
}
