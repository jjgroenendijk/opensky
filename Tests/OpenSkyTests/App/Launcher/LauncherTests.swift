// The launcher's registry ids, its page cache, its mode buttons, and the load
// panel. The unit test host withholds the install, so play stays disabled here.

import AppKit
@testable import OpenSky
import OpenSkyLaunch
import OpenSkyWorld
import Testing

@MainActor
struct LauncherTests {
    private final class RecordingActions: LauncherActions {
        var started: [LaunchMode] = []
        var folderChanges = 0
        var cancels = 0

        func start(_ mode: LaunchMode) {
            started.append(mode)
        }

        func gameFolderDidChange() {
            folderChanges += 1
        }

        func cancelLoad() {
            cancels += 1
        }
    }

    @Test func registryIdsArePinned() {
        #expect(LauncherRegistry.modes.map(\.controlIdentifier) == [
            "LaunchPlayControl", "LaunchDeveloperControl"
        ])
        #expect(LauncherRegistry.modes.map(\.mode) == LaunchMode.allCases)
        #expect(LauncherRegistry.pages.map(\.sidebarIdentifier) == [
            "LauncherPage-launch", "LauncherPage-assetCache", "LauncherPage-settings"
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

    @Test func loadPanelReplacesTheModeButtonsUntilTheLoadEnds() throws {
        let actions = RecordingActions()
        let page = LaunchPageViewController(actions: actions)
        page.loadViewIfNeeded()
        let play = try #require(button("LaunchPlayControl", in: page.view))
        let bar = try #require(find("LauncherLoadProgressIndicator", in: page.view))
        #expect(bar.isHiddenOrHasHiddenAncestor)

        var timeline = WorldLoadTimeline()
        timeline.apply(WorldLoadEvent(stage: .packages, kind: .started))
        timeline.apply(WorldLoadEvent(stage: .dialogue, kind: .finished(.milliseconds(1400))))
        page.showLoad(timeline, elapsed: .milliseconds(2000))

        #expect(play.isHiddenOrHasHiddenAncestor)
        #expect((bar as? NSProgressIndicator)?.doubleValue == timeline.fraction)
        let status = try #require(
            find("LauncherLoadStatusStatsLabel", in: page.view) as? NSTextField
        )
        #expect(status.stringValue.hasSuffix("2.00 s — AI packages"))
        #expect(find("LauncherLoadStageList", in: page.view) != nil)
        let dialogue = try #require(find("LauncherLoadStage-dialogue", in: page.view))
        #expect(dialogue.accessibilityValue() as? String == "1.40 s")

        try #require(button("LauncherCancelLoadControl", in: page.view)).performClick(nil)
        #expect(actions.cancels == 1)

        page.endLoad()
        #expect(!play.isHiddenOrHasHiddenAncestor)
        #expect(bar.isHiddenOrHasHiddenAncestor)
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
