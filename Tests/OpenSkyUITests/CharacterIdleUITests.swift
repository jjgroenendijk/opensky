// World > AI & Navigation, the Idles and Head Assembly sections. Unit tests pin
// the ids; only a UI test proves they are reachable.

import XCTest

final class CharacterIdleUITests: OpenSkyUITestCase {
    /// The idle-marker list is readable and every idle and head control shows.
    @MainActor
    func testIdleMarkerListAndHeadSourceAreReachable() throws {
        let app = try launchApp()
        selectDestination("Destination-aiNavigation", in: app)

        let markers = app.staticTexts["IdleMarkersLabel"]
        XCTAssertTrue(markers.waitForExistence(timeout: 5))
        let text = markers.value as? String ?? ""
        XCTAssertTrue(text.hasPrefix("Idle markers:"), text)

        XCTAssertTrue(app.checkBoxes["IdleMarkersControl"].exists)
        XCTAssertTrue(app.popUpButtons["IdleMarkerControl"].exists)
        XCTAssertTrue(app.popUpButtons["IdleEntryControl"].exists)
        XCTAssertTrue(app.checkBoxes["IdleIgnoreConditionsControl"].exists)
        XCTAssertTrue(app.buttons["IdleFireControl"].exists)
        XCTAssertTrue(app.buttons["IdlePickControl"].exists)
        XCTAssertTrue(app.staticTexts["IdleStatsLabel"].exists)
        XCTAssertTrue(app.popUpButtons["HeadSourceControl"].exists)
        XCTAssertTrue(app.staticTexts["HeadAssemblyStatsLabel"].exists)
    }
}
