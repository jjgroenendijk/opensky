// The launcher: the app opens on it, shows its pages with the game folder under
// Settings, and each launch mode button opens its window.

import XCTest

final class LauncherUITests: OpenSkyUITestCase {
    @MainActor
    func testLauncherOpensDeveloperModeAndReturns() throws {
        let app = try launchApp(launchMode: "")
        XCTAssertTrue(app.tables["LauncherSidebar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["LauncherGameFolderStatsLabel"].exists)
        XCTAssertTrue(app.buttons["LauncherSettingsLinkControl"].exists)
        XCTAssertTrue(app.buttons["LaunchPlayControl"].isEnabled)

        app.buttons["LaunchDeveloperControl"].click()
        XCTAssertTrue(app.outlines["AppSidebar"].waitForExistence(timeout: 10))

        app.typeKey("l", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["LaunchPlayControl"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.outlines["AppSidebar"].exists)
    }

    @MainActor
    func testPlayNeedsAGameFolder() {
        let app = launchApp(dataRoot: "/invalid/opensky-uitest-root", launchMode: "")
        XCTAssertTrue(app.buttons["LaunchPlayControl"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["LaunchPlayControl"].isEnabled)
        XCTAssertTrue(app.buttons["LaunchDeveloperControl"].isEnabled)
    }

    @MainActor
    func testLaunchPageShowsTheStartAndLinksToAssetOptimisation() throws {
        let app = try launchApp(launchMode: "")
        XCTAssertTrue(app.buttons["LaunchContinueControl"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["LauncherContinueStatsLabel"].exists)
        XCTAssertTrue(app.popUpButtons["LaunchStartKindControl"].exists)
        XCTAssertTrue(app.staticTexts["LaunchPlaySummaryStatsLabel"].exists)
        XCTAssertTrue(app.staticTexts["LauncherAssetOptimisationStatusStatsLabel"].exists)

        app.buttons["LauncherAssetOptimisationLinkControl"].click()
        XCTAssertTrue(app.buttons["AssetOptimisationConvertControl"].waitForExistence(timeout: 5))
        for identifier in [
            "AssetOptimisationEnabledControl",
            "AssetOptimisationDirectLoadControl"
        ] {
            XCTAssertTrue(app.checkBoxes[identifier].exists, identifier)
        }
        XCTAssertTrue(app.popUpButtons["AssetOptimisationTextureQualityControl"].exists)
        XCTAssertTrue(app.buttons["AssetOptimisationClearControl"].exists)
        XCTAssertTrue(app.staticTexts["AssetOptimisationStatusStatsLabel"].exists)
    }

    @MainActor
    func testDiagnosticsSettingsAndGraphicsPagesShowTheirControls() throws {
        let app = try launchApp(launchMode: "")
        let sidebar = app.tables["LauncherSidebar"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.descendants(matching: .any)["LauncherPage-diagnostics"].firstMatch.click()
        XCTAssertTrue(app.buttons["DiagnosticsOpenLogsControl"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["DiagnosticsCopyReportControl"].exists)
        XCTAssertTrue(app.buttons["DiagnosticsBenchmarkControl"].exists)

        sidebar.descendants(matching: .any)["LauncherPage-settings"].firstMatch.click()
        XCTAssertTrue(app.buttons["SettingsChooseGameFolderControl"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["SettingsInstallStatsLabel"].exists)

        sidebar.descendants(matching: .any)["LauncherPage-graphics"].firstMatch.click()
        XCTAssertTrue(app.popUpButtons["GraphicsPresetControl"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.checkBoxes["GraphicsFullScreenControl"].exists)
        XCTAssertTrue(app.popUpButtons["GraphicsFrameRateCapControl"].exists)
        XCTAssertTrue(app.textFields["GraphicsOptionfTreeLoadDistanceControl"].exists)
    }
}
