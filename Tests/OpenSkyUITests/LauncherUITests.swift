// The launcher: the app opens on it, shows its pages with the game folder under
// Settings, and the Play button opens the game window.

import XCTest

final class LauncherUITests: OpenSkyUITestCase {
    @MainActor
    func testLauncherShowsPlayAndTheGameFolder() throws {
        let app = try launchApp(skipsLauncher: false)
        XCTAssertTrue(app.tables["LauncherSidebar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["LauncherGameFolderStatsLabel"].exists)
        XCTAssertTrue(app.buttons["LauncherSettingsLinkControl"].exists)
        XCTAssertTrue(app.buttons["LaunchPlayControl"].isEnabled)
    }

    @MainActor
    func testPlayNeedsAGameFolder() {
        let app = launchApp(dataRoot: "/invalid/opensky-uitest-root", skipsLauncher: false)
        XCTAssertTrue(app.buttons["LaunchPlayControl"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["LaunchPlayControl"].isEnabled)
    }

    @MainActor
    func testLaunchPageShowsTheStartAndLinksToAssetOptimisation() throws {
        let app = try launchApp(skipsLauncher: false)
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
        let app = try launchApp(skipsLauncher: false)
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

    @MainActor
    func testLauncherGraphicsPageControls() throws {
        let app = try launchApp(skipsLauncher: false)
        let sidebar = app.tables["LauncherSidebar"]
        let page = sidebar.descendants(matching: .any)["LauncherPage-graphics"].firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        page.click()

        XCTAssertTrue(
            app.checkBoxes["GraphicsPipelineCacheControl"].waitForExistence(timeout: 5)
        )
        for checkbox in [
            "GraphicsGPUCullingControl", "GraphicsTextureStreamingControl",
            "GraphicsRayTracedShadowsControl", "GraphicsFrameInterpolationControl",
            "GraphicsMeshShaderGrassControl"
        ] {
            XCTAssertTrue(app.checkBoxes[checkbox].exists, checkbox)
        }
        XCTAssertTrue(app.buttons["GraphicsPipelineCacheClearControl"].exists)
        for popUp in [
            "GraphicsTextureBudgetControl", "GraphicsRenderScaleControl", "GraphicsUpscalerControl"
        ] {
            XCTAssertTrue(app.popUpButtons[popUp].exists, popUp)
        }
        XCTAssertTrue(app.staticTexts["GraphicsStatsLabel"].exists)
    }
}
