// Developer > Rendering Performance and the launcher Graphics page: every M33 control
// is reachable. Unit tests pin the ids; only a UI test proves a user can reach them.

import XCTest

final class RenderingPerformanceUITests: OpenSkyUITestCase {
    @MainActor
    func testRenderingPerformanceControlsAndReadouts() throws {
        let app = try launchApp()
        selectDestination("Destination-renderingPerformance", in: app)

        XCTAssertTrue(app.staticTexts["RenderTargetsStatsLabel"].waitForExistence(timeout: 5))
        for checkbox in [
            "PipelineCacheEnabledControl", "GPUCullingEnabledControl",
            "TextureStreamingEnabledControl", "RayTracedShadowsEnabledControl",
            "RayTracedShadowsViewControl"
        ] {
            XCTAssertTrue(app.checkBoxes[checkbox].exists, checkbox)
        }
        XCTAssertTrue(app.buttons["PipelineCacheClearControl"].exists)
        XCTAssertTrue(app.popUpButtons["TextureBudgetControl"].exists)
        for label in [
            "PipelineCacheStatsLabel", "GPUCullingStatsLabel", "TextureStreamingStatsLabel",
            "RayTracedShadowsStatsLabel"
        ] {
            XCTAssertTrue(app.staticTexts[label].exists, label)
        }
    }

    @MainActor
    func testLauncherGraphicsPageControls() throws {
        let app = try launchApp(launchMode: "")
        let sidebar = app.tables["LauncherSidebar"]
        let page = sidebar.descendants(matching: .any)["LauncherPage-graphics"].firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        page.click()

        XCTAssertTrue(
            app.checkBoxes["GraphicsPipelineCacheControl"].waitForExistence(timeout: 5)
        )
        for checkbox in [
            "GraphicsGPUCullingControl", "GraphicsTextureStreamingControl",
            "GraphicsRayTracedShadowsControl"
        ] {
            XCTAssertTrue(app.checkBoxes[checkbox].exists, checkbox)
        }
        XCTAssertTrue(app.buttons["GraphicsPipelineCacheClearControl"].exists)
        XCTAssertTrue(app.popUpButtons["GraphicsTextureBudgetControl"].exists)
        XCTAssertTrue(app.staticTexts["GraphicsStatsLabel"].exists)
    }
}
