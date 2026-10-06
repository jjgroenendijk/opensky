// Library > Skyrim Saves: literal ids, the empty state, and how a synthetic `.ess`
// becomes a load-list row marked as an import.

import AppKit
import FormatsTesting
import Foundation
@testable import OpenSky
import OpenSkyAgentControl
import OpenSkyFormatsESM
import OpenSkyMenus
import OpenSkySave
import Testing

@MainActor
struct SkyrimSavesPanelTests {
    @Test func accessibilityIdentifiersArePinned() {
        let panel = SkyrimSavesViewController()
        panel.loadViewIfNeeded()
        #expect(panel.view.accessibilityIdentifier() == "SkyrimSaves")
        #expect(panel.tableView.accessibilityIdentifier() == "SkyrimSavesTable")
        #expect(panel.folderLabel.accessibilityIdentifier() == "SkyrimSavesFolderStatsLabel")
        #expect(panel.pictureView.accessibilityIdentifier() == "SkyrimSavesPictureView")
        #expect(panel.inspectionView.accessibilityIdentifier() == "SkyrimSavesInspectionText")
        #expect(panel.chooseControl.accessibilityIdentifier() == "SkyrimSavesChooseControl")
        #expect(panel.reloadControl.accessibilityIdentifier() == "SkyrimSavesReloadControl")
        #expect(panel.dryRunControl.accessibilityIdentifier() == "SkyrimSavesDryRunControl")
    }

    @Test func withoutAFolderNothingIsListedAndDryRunIsOff() {
        guard ProcessInfo.processInfo.environment[ESSSaveFolderSetting.environmentKey] == nil
        else { return }
        let panel = SkyrimSavesViewController()
        panel.loadViewIfNeeded()
        #expect(panel.folderLabel.stringValue == "No Skyrim saves folder is set.")
        #expect(panel.listings.isEmpty)
        #expect(!panel.dryRunControl.isEnabled)
        #expect(panel.inspectionView.string == "Save: none")
    }

    @Test func aSkyrimSaveBecomesAnImportRow() throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "ess-rows-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try ESSFixture().build().write(to: folder.appending(path: "Save7.ess"))
        let listing = try #require(try ESSSaveFolder(directory: folder).listings().first)
        let row = SkyrimSaveImportAdapter.row(listing)
        #expect(row.isImport)
        #expect(SkyrimSaveImportAdapter.isImport(row.slot))
        #expect(row.title == "Skyrim import: Save7 - Prisoner")
        #expect(row.detail == "Level 3, Helgen Keep")
        #expect(row.character?.race == "NordRace")
        #expect(row.picture?.width == 2)
    }

    @Test func teleportGoesToTheInteriorOrThePosition() {
        let space = ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x5000)
        let interior = ESSImportedPlacement(
            space: space, isInterior: true, spaceEditorID: "HelgenKeep01",
            position: .zero, heading: nil, cell: nil
        )
        #expect(SkyrimSaveImportAdapter.teleportTarget(interior) == .cell("HelgenKeep01"))
        let exterior = ESSImportedPlacement(
            space: space, isInterior: false, spaceEditorID: "Tamriel",
            position: SIMD3(1, 2, 3), heading: nil, cell: nil
        )
        #expect(SkyrimSaveImportAdapter.teleportTarget(exterior) == .position(SIMD3(1, 2, 3)))
    }
}
