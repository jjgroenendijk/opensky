// The launcher's registry ids, its page cache, its Play button, the start
// options, the new game options, Continue, the load readout, and the install check on
// Settings. The unit test host withholds the install, so play stays disabled here.

import AppKit
@testable import OpenSky
import OpenSkyCells
import OpenSkyGameData
import OpenSkyLaunch
import OpenSkyLoading
import OpenSkySave
import OpenSkyWorld
import Testing

@MainActor
struct LauncherTests {
    private final class RecordingActions: LauncherActions {
        var plays = 0
        var continued: [String] = []
        var folderChanges = 0
        var cancels = 0
        var benchmarks: [BenchmarkRequest] = []

        func play() {
            plays += 1
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

        func runBenchmark(_ request: BenchmarkRequest) {
            benchmarks.append(request)
        }
    }

    @Test func registryIdsArePinned() {
        #expect(LauncherRegistry.pages.map(\.sidebarIdentifier) == [
            "LauncherPage-launch", "LauncherPage-assetOptimisation", "LauncherPage-graphics",
            "LauncherPage-benchmark", "LauncherPage-diagnostics", "LauncherPage-settings"
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
        launcher.showPage(id: "diagnostics")
        #expect(launcher.currentPageID == "diagnostics")
        launcher.showPage(id: "launch")
        #expect(launcher.currentPageID == "launch")
    }

    @Test func benchmarkPageRunsTheChosenPresetWithItsOptions() throws {
        let actions = RecordingActions()
        let page = BenchmarkPageViewController(context: LauncherContext(actions: actions))
        page.loadViewIfNeeded()
        try page.presetControl
            .selectItem(at: #require(BenchmarkPreset.allCases.firstIndex(of: .quick)))
        page.overlayControl.state = .off
        page.loadPassesControl.state = .off
        page.screenshotsControl.state = .on
        #expect(page.fullScreenControl.state == .on)
        page.fullScreenControl.state = .off
        let run = try #require(button("BenchmarkRunControl", in: page.view))
        run.performClick(nil)
        let request = try #require(actions.benchmarks.first)
        #expect(request.preset == .quick)
        #expect(!request.overlay)
        #expect(!request.loadPasses)
        #expect(request.screenshots)
        #expect(!request.fullScreen)
        #expect(page.fullScreenControl.accessibilityIdentifier() == "BenchmarkFullScreenControl")
        #expect(page.presetControl.accessibilityIdentifier() == "BenchmarkPresetControl")
        #expect(page.overlayControl.accessibilityIdentifier() == "BenchmarkOverlayControl")
        #expect(page.resultLabel.accessibilityIdentifier() == "BenchmarkResultStatsLabel")
    }

    @Test func playFollowsTheGameFolder() throws {
        let actions = RecordingActions()
        let page = LaunchPageViewController(context: LauncherContext(actions: actions))
        page.loadViewIfNeeded()
        let status = GameFolderStatus()
        let play = try #require(button("LaunchPlayControl", in: page.view))
        #expect(play.isEnabled == status.isFound)
        #expect(find("LaunchPlaySummaryStatsLabel", in: page.view) != nil)
        #expect(find("LauncherGameFolderStatsLabel", in: page.view) != nil)
        #expect(find("LauncherSettingsLinkControl", in: page.view) != nil)
        #expect(find("LauncherChooseGameFolderControl", in: page.view) == nil)
    }

    @Test func loadPanelReplacesThePlayButtonUntilTheLoadEnds() throws {
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
        #expect(page.continueButton.isEnabled == status.isFound)
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

    @Test func survivalModeIsOffAndUnaskedByDefaultAndTheBoxesWriteTheSettings() throws {
        let store = PlayerSettingsStore(persistence: nil)
        let context = LauncherContext(actions: RecordingActions())
        context.playerSettings = { store }
        let page = LaunchPageViewController(context: context)
        page.loadViewIfNeeded()
        let survival = try #require(button("LaunchSurvivalModeControl", in: page.view))
        let ask = try #require(button("LaunchSurvivalModeAskControl", in: page.view))
        #expect(survival.state == .off)
        #expect(ask.state == .off)
        survival.performClick(nil)
        #expect(store.bool(.survivalMode))
        ask.performClick(nil)
        #expect(store.bool(.survivalModeAsk))
        #expect(!survival.isEnabled)
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
