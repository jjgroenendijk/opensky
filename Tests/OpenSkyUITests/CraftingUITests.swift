// World > Inventory & Equipment > Crafting UI test. Unit tests pin the ids;
// only a UI test proves they are reachable. The verdict half needs the install.

import XCTest

final class CraftingUITests: OpenSkyUITestCase {
    @MainActor
    func testCraftingControlsAreReachable() throws {
        let app = try launchApp()
        selectDestination("Destination-inventoryEquipment", in: app)
        XCTAssertTrue(app.popUpButtons["CraftingStationControl"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["CraftingOpenControl"].exists)
        XCTAssertTrue(app.popUpButtons["CraftingRecipeControl"].exists)
        XCTAssertTrue(app.buttons["CraftingCraftControl"].exists)
        XCTAssertTrue(app.buttons["HarvestForceControl"].exists)
        XCTAssertTrue(app.staticTexts["CraftingStatsLabel"].exists)
        XCTAssertTrue(app.staticTexts["HarvestStatsLabel"].exists)
    }

    /// Opens the forge from the station list and reads a recipe verdict.
    @MainActor
    func testOpeningTheForgeShowsRecipeVerdicts() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let root = environment["OPENSKY_DATA_ROOT"], !root.isEmpty else {
            throw XCTSkip("OPENSKY_DATA_ROOT not set for UI-test runner")
        }
        let app = launchApp(dataRoot: root)
        selectDestination("Destination-inventoryEquipment", in: app)
        let stations = app.popUpButtons["CraftingStationControl"]
        XCTAssertTrue(stations.waitForExistence(timeout: 30))
        stations.click()
        let forge = app.menuItems["CraftingSmithingForge"]
        XCTAssertTrue(forge.waitForExistence(timeout: 30))
        forge.click()
        app.buttons["CraftingOpenControl"].click()

        let readout = app.staticTexts["CraftingStatsLabel"]
        let verdict = NSPredicate { label, _ in
            let text = (label as? XCUIElement)?.value as? String ?? ""
            return text.contains("Station: CraftingSmithingForge")
                && (text.contains(": missing") || text.contains(": needs")
                    || text.contains(": ready"))
        }
        let shown = expectation(for: verdict, evaluatedWith: readout)
        wait(for: [shown], timeout: 10)
    }
}
