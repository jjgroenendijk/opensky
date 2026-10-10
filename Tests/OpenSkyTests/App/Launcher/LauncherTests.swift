// The launcher's registry ids, its page cache, its mode buttons, the start
// options, Continue, the load panel, and the install check on Settings. The unit test host
// withholds the
// install, so play stays disabled here.

import AppKit
@testable import OpenSky
import OpenSkyLaunch
import OpenSkySave
import OpenSkyWorld
import Testing

@MainActor
struct LauncherTests {
    private final class RecordingActions: LauncherActions {
        var started: [LaunchMode] = []
        var continued: [String] = []
        var folderChanges = 0
        var cancels = 0

        func start(_ mode: LaunchMode) {
            started.append(mode)
        }

        func continueGame(slot: String) {
            continued.append(slot)
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
            "LauncherPage-launch", "LauncherPage-assetOptimisation", "LauncherPage-graphics",
            "LauncherPage-diagnostics", "LauncherPage-settings"
        ])
        #expect(LauncherRegistry.modes.allSatisfy { !$0.summary.isEmpty })
        #expect(LauncherRegistry.page(id: LauncherRegistry.defaultPageID) != nil)
    }

    @Test func launcherOpensOnTheLaunchPageAndCachesPages() {
        let actions = RecordingActions()
        let launcher = LauncherViewController(actions: actions)
        launcher.loadViewIfNeeded()
        #expect(launcher.currentPageID == "launch")
        launcher.showPage(id: "settings")
        #expect(launcher.currentPageID == "settings")
        launcher.showPage(id: "diagnostics")
        #expect(launcher.currentPageID == "diagnostics")
        launcher.showPage(id: "launch")
        #expect(launcher.currentPageID == "launch")
    }

    @Test func modeButtonsFollowTheGameFolder() throws {
        let actions = RecordingActions()
        let page = LaunchPageViewController(context: LauncherContext(actions: actions))
        page.loadViewIfNeeded()
        let status = GameFolderStatus()
        let play = try #require(button("LaunchPlayControl", in: page.view))
        let developer = try #require(button("LaunchDeveloperControl", in: page.view))
        #expect(play.isEnabled == status.canStart(.play))
        #expect(developer.isEnabled)
        #expect(find("LauncherGameFolderStatsLabel", in: page.view) != nil)
        #expect(find("LauncherSettingsLinkControl", in: page.view) != nil)
        #expect(find("LauncherChooseGameFolderControl", in: page.view) == nil)

        developer.performClick(nil)
        #expect(actions.started == [.developer])
    }

    @Test func loadPanelReplacesTheModeButtonsUntilTheLoadEnds() throws {
        let actions = RecordingActions()
        let page = LaunchPageViewController(context: LauncherContext(actions: actions))
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

    @Test func settingsShowsTheInstallCheck() throws {
        let page = SettingsViewController()
        page.loadViewIfNeeded()
        var summary = GameInstallSummary()
        summary.archives = 2
        summary.problems = [GameInstallProblem(
            kind: .missingMaster, subject: "Update.esm", message: "Update.esm is missing",
            fix: "Verify the game files in Steam"
        )]
        page.show(summary)
        let problems = try #require(
            find("SettingsInstallProblemsStatsLabel", in: page.view) as? NSTextField
        )
        #expect(problems.stringValue
            == "Problem: Update.esm is missing. Verify the game files in Steam.")
        #expect(!problems.isHidden)
        let counts = try #require(
            find("SettingsInstallCountsStatsLabel", in: page.view) as? NSTextField
        )
        #expect(counts.stringValue == "2 archives, 0 plugins, 0 records")
        #expect(find("SettingsInstallStatsLabel", in: page.view) != nil)
        #expect(find("SettingsChooseGameFolderControl", in: page.view) != nil)
    }

    @Test func anInvalidStartTurnsPlayOffAndSaysWhy() throws {
        let saved = LaunchPreferences.savedStart()
        defer { LaunchPreferences.remember(saved) }
        let page = LaunchPageViewController(context: LauncherContext(actions: RecordingActions()))
        page.loadViewIfNeeded()
        page.startKindPopUp.selectItem(at: LaunchStartForm.Kind.cell.rawValue)
        page.startKindPopUp.sendAction(page.startKindPopUp.action, to: page.startKindPopUp.target)
        let play = try #require(button("LaunchPlayControl", in: page.view))
        #expect(!play.isEnabled)
        #expect(page.startReasonLabel.stringValue.hasPrefix("Play is off: "))
        #expect(!page.startCellField.isHidden)
        #expect(page.startXField.isHidden)
        page.startKindPopUp.selectItem(at: LaunchStartForm.Kind.normal.rawValue)
        page.startKindPopUp.sendAction(page.startKindPopUp.action, to: page.startKindPopUp.target)
        #expect(page.startReasonLabel.isHidden)
    }

    @Test func continueLoadsTheNewestSaveOrSaysWhyNot() throws {
        let actions = RecordingActions()
        let page = LaunchPageViewController(context: LauncherContext(actions: actions))
        page.loadViewIfNeeded()
        page.show(ContinueOffer.noSaves)
        let label = try #require(find("LauncherContinueStatsLabel", in: page.view) as? NSTextField)
        #expect(label.stringValue == "Unavailable: No saves yet")
        #expect(!page.continueButton.isEnabled)
        page.show(ContinueOffer(
            slot: "quick",
            title: "Lydia, level 12",
            date: nil,
            disabledReason: nil
        ))
        #expect(label.stringValue == "Lydia, level 12")
        let status = GameFolderStatus()
        #expect(page.continueButton.isEnabled == status.canStart(.play))
        if page.continueButton.isEnabled {
            page.continueButton.performClick(nil)
            #expect(actions.continued == ["quick"])
        }
    }

    @Test func theAssetStatusLinksToItsPage() throws {
        let context = LauncherContext(actions: RecordingActions())
        var shown: [String] = []
        context.showPage = { shown.append($0) }
        let page = LaunchPageViewController(context: context)
        page.loadViewIfNeeded()
        #expect(find("LauncherAssetOptimisationStatusStatsLabel", in: page.view) != nil)
        try #require(button("LauncherAssetOptimisationLinkControl", in: page.view))
            .performClick(nil)
        #expect(shown == ["assetOptimisation"])
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
