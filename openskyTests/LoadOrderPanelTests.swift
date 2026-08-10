// Library > Load Order verification-surface coverage: the literal
// accessibility-id contract, the geometry of the controls, and the rows the
// table shows for a synthetic install (issue #73).

import AppKit
@testable import opensky
import Testing

@MainActor
struct LoadOrderPanelTests {
    /// A temp install with two plugins and a plugins.txt naming one of them.
    private static func makeRoot() throws -> GameDataRoot {
        let install = FileManager.default.temporaryDirectory
            .appending(path: "opensky-loadorder-\(UUID().uuidString)", directoryHint: .isDirectory)
        let data = install.appending(path: "Data", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        for name in ["Skyrim.esm", "Mod.esp"] {
            try Data().write(to: data.appending(path: name, directoryHint: .notDirectory))
        }
        try Data("*Mod.esp\n".utf8).write(
            to: install.appending(path: "plugins.txt", directoryHint: .notDirectory)
        )
        return GameDataRoot(installURL: install, dataURL: data, source: .environment)
    }

    private static func makePanel(root: GameDataRoot?) -> LoadOrderViewController {
        let panel = LoadOrderViewController()
        panel.gameDataRoot = root
        panel.startupErrorMessage = root == nil ? "Game data not located." : nil
        panel.loadViewIfNeeded()
        return panel
    }

    @Test func accessibilityIdentifiersArePinned() throws {
        let panel = try Self.makePanel(root: Self.makeRoot())

        #expect(panel.view.accessibilityIdentifier() == "LoadOrder")
        #expect(panel.tableView.accessibilityIdentifier() == "LoadOrderTable")
        #expect(panel.summaryLabel.accessibilityIdentifier() == "LoadOrderStatsLabel")
        #expect(panel.pathLabel.accessibilityIdentifier() == "LoadOrderPathLabel")
        #expect(panel.sourceLabel.accessibilityIdentifier() == "LoadOrderSourceLabel")
        #expect(panel.chooseControl.accessibilityIdentifier() == "LoadOrderChooseControl")
        #expect(panel.useDefaultControl.accessibilityIdentifier() == "LoadOrderUseDefaultControl")
        #expect(panel.reloadControl.accessibilityIdentifier() == "LoadOrderReloadControl")
    }

    @Test func controlsHaveVisibleFrames() throws {
        let panel = try Self.makePanel(root: Self.makeRoot())
        panel.view.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        panel.view.layoutSubtreeIfNeeded()

        for control: NSView in [
            panel.chooseControl, panel.useDefaultControl, panel.reloadControl,
            panel.tableView, panel.summaryLabel, panel.pathLabel
        ] {
            #expect(!control.isHidden)
            #expect(control.frame.height > 0)
        }
    }

    @Test func tableListsTheResolvedOrderForTheConfiguredRoot() throws {
        let panel = try Self.makePanel(root: Self.makeRoot())

        #expect(panel.rows.map(\.name) == ["Skyrim.esm", "Mod.esp"])
        #expect(panel.tableView.numberOfRows == 2)
        #expect(panel.tableView.tableColumns.count == 4)
        #expect(panel.summaryLabel.stringValue.hasPrefix("2 active plugins"))
        #expect(panel.pathLabel.stringValue.hasSuffix("plugins.txt"))
    }

    /// No install located -> the panel says so instead of listing nothing
    /// without explanation.
    @Test func missingRootExplainsItselfAndListsNothing() {
        let panel = Self.makePanel(root: nil)

        #expect(panel.rows.isEmpty)
        #expect(panel.pathLabel.stringValue == "Not located")
        #expect(panel.sourceLabel.stringValue == "Game data not located.")
    }

    /// A Settings data-root change reaches the cached panel in place.
    @Test func reloadFullContentSwapsTheRoot() throws {
        let panel = Self.makePanel(root: nil)

        try panel.reloadFullContent(context: FullContentContext(
            gameDataRoot: Self.makeRoot(),
            startupErrorMessage: nil
        ))

        #expect(panel.rows.map(\.name) == ["Skyrim.esm", "Mod.esp"])
    }
}
