// World > Inventory & Equipment > Locks and World > World > Traps UI test. Unit
// tests pin the ids; only a UI test proves both surfaces are reachable.

import XCTest

final class LockTrapUITests: OpenSkyUITestCase {
    @MainActor
    func testLockControlsAreReachable() throws {
        let app = try launchApp()
        selectDestination("Destination-inventoryEquipment", in: app)
        XCTAssertTrue(app.popUpButtons["LockSelectControl"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["LockUnlockControl"].exists)
        XCTAssertTrue(app.buttons["LockRelockControl"].exists)
        XCTAssertTrue(app.buttons["LockPickControl"].exists)
        XCTAssertTrue(app.checkBoxes["LockCarriesKeyControl"].exists)
        XCTAssertTrue(app.staticTexts["LockStatsLabel"].exists)
    }

    @MainActor
    func testTrapControlsAreReachable() throws {
        let app = try launchApp()
        selectDestination("Destination-world", in: app)
        XCTAssertTrue(app.popUpButtons["TrapSelectControl"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["TrapFireControl"].exists)
        XCTAssertTrue(app.buttons["TrapDisarmControl"].exists)
        XCTAssertTrue(app.staticTexts["TrapStatsLabel"].exists)
    }
}
