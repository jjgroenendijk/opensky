// The launcher's registry ids, its page cache, and its mode buttons. The unit
// test host withholds the install, so play stays disabled here.

import AppKit
@testable import OpenSky
import OpenSkyLaunch
import Testing

@MainActor
struct LauncherTests {
    private final class RecordingActions: LauncherActions {
        var started: [LaunchMode] = []
        var folderChanges = 0

        func start(_ mode: LaunchMode) {
            started.append(mode)
        }

        func gameFolderDidChange() {
            folderChanges += 1
        }
    }

    @Test func registryIdsArePinned() {
        #expect(LauncherRegistry.modes.map(\.controlIdentifier) == [
            "LaunchPlayControl", "LaunchDeveloperControl"
        ])
        #expect(LauncherRegistry.modes.map(\.mode) == LaunchMode.allCases)
        #expect(LauncherRegistry.pages.map(\.sidebarIdentifier) == [
            "LauncherPage-launch", "LauncherPage-settings"
        ])
        #expect(LauncherRegistry.page(id: LauncherRegistry.defaultPageID) != nil)
    }

    @Test func launcherOpensOnTheLaunchPageAndCachesPages() {
        let actions = RecordingActions()
        let launcher = LauncherViewController(actions: actions)
        launcher.loadViewIfNeeded()
        #expect(launcher.currentPageID == "launch")
        launcher.showPage(id: "settings")
        #expect(launcher.currentPageID == "settings")
        launcher.showPage(id: "launch")
        #expect(launcher.currentPageID == "launch")
    }

    @Test func modeButtonsFollowTheGameFolder() throws {
        let actions = RecordingActions()
        let page = LaunchPageViewController(actions: actions)
        page.loadViewIfNeeded()
        let status = GameFolderStatus()
        let play = try #require(button("LaunchPlayControl", in: page.view))
        let developer = try #require(button("LaunchDeveloperControl", in: page.view))
        #expect(play.isEnabled == status.canStart(.play))
        #expect(developer.isEnabled)
        #expect(find("LauncherGameFolderStatsLabel", in: page.view) != nil)
        #expect(find("LauncherChooseGameFolderControl", in: page.view) != nil)

        developer.performClick(nil)
        #expect(actions.started == [.developer])
    }

    private func button(_ identifier: String, in view: NSView) -> NSButton? {
        find(identifier, in: view) as? NSButton
    }

    private func find(_ identifier: String, in view: NSView) -> NSView? {
        if view.accessibilityIdentifier() == identifier {
            return view
        }
        return view.subviews.lazy.compactMap { find(identifier, in: $0) }.first
    }
}
