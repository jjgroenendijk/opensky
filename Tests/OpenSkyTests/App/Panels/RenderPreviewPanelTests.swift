// Library > Render Preview: literal ids, the empty state, and how the controls become a
// preview request.

import AppKit
@testable import OpenSky
import OpenSkyPreview
import Testing

@MainActor
struct RenderPreviewPanelTests {
    @Test func accessibilityIdentifiersArePinned() {
        let panel = RenderPreviewViewController()
        panel.loadViewIfNeeded()
        #expect(panel.view.accessibilityIdentifier() == "RenderPreview")
        #expect(panel.kindControl.accessibilityIdentifier() == "RenderPreviewKindControl")
        #expect(panel.targetControl.accessibilityIdentifier() == "RenderPreviewTargetControl")
        #expect(panel.cellControl.accessibilityIdentifier() == "RenderPreviewCellControl")
        #expect(panel.stageControl.accessibilityIdentifier() == "RenderPreviewStageControl")
        #expect(panel.angleControl.accessibilityIdentifier() == "RenderPreviewAngleControl")
        #expect(panel.timeControl.accessibilityIdentifier() == "RenderPreviewHourControl")
        #expect(panel.weatherControl.accessibilityIdentifier() == "RenderPreviewWeatherControl")
        #expect(panel.renderControl.accessibilityIdentifier() == "RenderPreviewRenderControl")
        #expect(panel.statsLabel.accessibilityIdentifier() == "RenderPreviewStatsLabel")
        #expect(panel.imageStack.accessibilityIdentifier() == "RenderPreviewImages")
    }

    @Test func withoutGameDataRenderIsOff() {
        let panel = RenderPreviewViewController()
        panel.loadViewIfNeeded()
        #expect(!panel.renderControl.isEnabled)
        #expect(panel.statsLabel.stringValue == "Views: game data not located")
    }

    @Test func theControlsOfferEveryStageAndAngle() {
        let panel = RenderPreviewViewController()
        panel.loadViewIfNeeded()
        #expect(panel.kindControl.itemTitles == ["Record", "Reference", "Mesh", "Cell"])
        #expect(panel.stageControl.itemTitles == ["Auto", "Studio", "Cell"])
        #expect(panel.angleControl.itemTitles == [
            "Front", "Side", "Back", "Top", "Three-Quarter", "All"
        ])
        #expect(panel.angleControl.titleOfSelectedItem == "Three-Quarter")
    }

    @Test func aRecordInACellOnAllAnglesBecomesOneRequest() throws {
        let panel = RenderPreviewViewController()
        panel.loadViewIfNeeded()
        panel.targetControl.stringValue = "HousecarlWhiterun"
        panel.cellControl.stringValue = "WhiterunBanneredMare"
        panel.angleControl.selectItem(withTitle: "All")
        let request = try #require(panel.currentRequest())
        #expect(request.target == .record("HousecarlWhiterun"))
        #expect(request.hostCell == .interiorCell("WhiterunBanneredMare"))
        #expect(request.resolvedStage == .cell)
        #expect(request.views.count == 5)
    }

    @Test func anEmptyTargetShowsTheReason() {
        let panel = RenderPreviewViewController()
        panel.loadViewIfNeeded()
        #expect(panel.currentRequest() == nil)
        #expect(panel.statsLabel.stringValue == "Views: \(PreviewError.oneTarget.description)")
    }
}
