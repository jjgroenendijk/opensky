// M18 acceptance surface: the existing Library > Asset Browser destination,
// its literal accessibility contract and visible record-browser geometry.

import AppKit
@testable import opensky
import Testing

@MainActor
struct M18AcceptancePanelTests {
    @Test
    func assetBrowserPublishesTheReferenceRecordControlsAndReadout() throws {
        let descriptor = try #require(DestinationRegistry.destination(id: "assetBrowser"))
        #expect(descriptor.sidebarIdentifier == "Destination-assetBrowser")
        guard case let .fullContent(makeController) = descriptor.content else {
            Issue.record("Library > Asset Browser is not full content")
            return
        }
        let context = FullContentContext(gameDataRoot: nil, startupErrorMessage: "test")
        let panel = try #require(makeController(context) as? PreviewViewController)
        panel.loadViewIfNeeded()

        #expect(panel.view.accessibilityIdentifier() == "AssetBrowser")
        #expect(panel.categoryPopUp.accessibilityIdentifier() == "AssetCategory")
        #expect(panel.pluginPopUp.accessibilityIdentifier() == "AssetPluginControl")
        #expect(panel.recordTypePopUp.accessibilityIdentifier() == "AssetRecordTypeControl")
        #expect(panel.searchField.accessibilityIdentifier() == "AssetFilter")
        #expect(panel.tableView.accessibilityIdentifier() == "AssetTable")
        #expect(panel.statusLabel.accessibilityIdentifier() == "AssetStatus")
        #expect(findView(id: "AssetRecordInspectorStatsLabel", in: panel.view) != nil)
    }

    @Test
    func recordControlsHaveVisibleGeometryForAllEightTypes() throws {
        let panel = PreviewViewController()
        panel.startupErrorMessage = "test"
        panel.loadViewIfNeeded()
        let recordIndex = try #require(
            PreviewCategory.allCases.firstIndex(of: .referenceRecords)
        )
        panel.categoryPopUp.selectItem(at: recordIndex)
        panel.categoryChanged()
        panel.view.frame = NSRect(x: 0, y: 0, width: 1100, height: 700)
        panel.view.layoutSubtreeIfNeeded()

        #expect(panel.recordTypePopUp.itemTitles.count == ReferenceRecordType.allCases.count)
        for control: NSView in [
            panel.pluginPopUp, panel.recordTypePopUp, panel.searchField,
            panel.tableView, panel.statusLabel
        ] {
            #expect(!control.isHidden)
            #expect(control.frame.height > 0)
        }
    }

    private func findView(id: String, in view: NSView) -> NSView? {
        if view.accessibilityIdentifier() == id {
            return view
        }
        for child in view.subviews {
            if let match = findView(id: id, in: child) {
                return match
            }
        }
        return nil
    }
}
