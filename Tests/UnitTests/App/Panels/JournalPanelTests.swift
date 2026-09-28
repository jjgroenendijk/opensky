// World > Quests & Journal verification-surface coverage (issue #184): the
// panel the registry factory builds, the literal accessibility-id contract, the
// readouts each section renders from one snapshot, and the provider round-trip
// for every control.

import AppKit
@testable import opensky
import Testing

struct JournalPanelTests {
    @Test @MainActor
    func registryFactoryBuildsThePanelWithProvidersWired() throws {
        let descriptor = try #require(DestinationRegistry.destination(id: "journal"))
        guard case let .worldInspector(makePanel) = descriptor.content else {
            Issue.record("journal is not a world inspector")
            return
        }
        let providers = FakeWorldProviders()
        let panel = try #require(
            makePanel(WorldPanelContext(providers: providers)) as? JournalPanelViewController
        )
        panel.loadViewIfNeeded()
        #expect(panel.provider === providers)
    }

    /// Accessibility ids are the UI-test API (docs/tools/app-ui.md); pin the
    /// journal set literally.
    @Test @MainActor
    func accessibilityIdentifiersArePinned() {
        let panel = JournalPanelViewController()
        panel.loadViewIfNeeded()
        #expect(panel.questsSection.sectionIdentifier == "journalQuests")
        #expect(panel.controlsSection.sectionIdentifier == "journalQuestControls")
        #expect(panel.pageSection.sectionIdentifier == "journalPage")

        #expect(panel.questControl.accessibilityIdentifier() == "JournalQuestControl")
        #expect(panel.startControl.accessibilityIdentifier() == "JournalStartQuestControl")
        #expect(panel.stopControl.accessibilityIdentifier() == "JournalStopQuestControl")
        #expect(panel.stageControl.accessibilityIdentifier() == "JournalStageControl")
        #expect(panel.setStageControl.accessibilityIdentifier() == "JournalSetStageControl")
        #expect(panel.openControl.accessibilityIdentifier() == "JournalOpenControl")
        #expect(panel.closeControl.accessibilityIdentifier() == "JournalCloseControl")
        #expect(
            panel.pageSection.completedControl.accessibilityIdentifier()
                == "JournalShowCompletedControl"
        )

        for identifier in [
            "JournalQuestsStatsLabel", "JournalSelectionStatsLabel", "JournalAliasStatsLabel",
            "JournalControlsStatsLabel", "JournalPageStatsLabel"
        ] {
            #expect(scriptsReadout(identifier, in: panel.view) != nil, "\(identifier) is missing")
        }
    }

    /// Layout invariant: no section control may be hidden or zero-height inside
    /// the panel's document view.
    @Test @MainActor
    func controlsHaveVisibleFramesInsideDocument() throws {
        let panel = JournalPanelViewController()
        let scrollView = try #require(panel.view as? NSScrollView)
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 900)
        panel.view.layoutSubtreeIfNeeded()

        for control: NSView in [
            panel.questControl, panel.startControl, panel.stopControl,
            panel.stageControl, panel.setStageControl, panel.openControl, panel.closeControl
        ] {
            #expect(!control.isHidden)
            #expect(control.frame.height > 0)
            let inDocument = control.convert(control.bounds, to: scrollView.documentView)
            #expect(inDocument.minY >= 0)
        }
    }

    // MARK: - Readouts

    @Test @MainActor
    func questsReadoutStatesTheSessionAndItsRows() {
        let panel = JournalPanelViewController()
        let providers = FakeWorldProviders()
        providers.journal.journalSnapshot = makeJournalSnapshot(
            questCount: 400,
            runningCount: 2,
            completedCount: 1,
            rows: [
                makeJournalRow(
                    editorID: "MGRArniel01", title: "Arniel's Endeavor",
                    kind: "mages guild", stage: 10
                ),
                makeJournalRow(editorID: "MQ101", title: "Unbound", isCompleted: true)
            ],
            droppedRowCount: 3
        )
        panel.provider = providers
        panel.loadViewIfNeeded()
        panel.questsSection.refreshReadout()

        let text = panel.questsSection.readout
        #expect(text.contains("Journal quests: 400"))
        #expect(text.contains("Running: 2"))
        #expect(text.contains("Completed: 1"))
        #expect(text.contains("MGRArniel01 \"Arniel's Endeavor\" (mages guild)"))
        #expect(text.contains("stage 10"))
        #expect(text.contains("stage -"))
        #expect(text.contains("and 3 more"))
    }

    /// A session with no plugin says so rather than showing zeros that would
    /// read as an empty index.
    @Test @MainActor
    func questsReadoutStatesAnUnavailableIndex() {
        let panel = JournalPanelViewController()
        let providers = FakeWorldProviders()
        providers.journal.journalSnapshot = makeJournalSnapshot(hasQuestIndex: false)
        panel.provider = providers
        panel.loadViewIfNeeded()
        panel.questsSection.refreshReadout()

        #expect(panel.questsSection.readout.contains("unavailable"))
    }

    @Test @MainActor
    func selectionReadoutShowsObjectivesAndJournalEntries() {
        let panel = JournalPanelViewController()
        let providers = FakeWorldProviders()
        providers.journal.journalSnapshot = makeJournalSnapshot(
            selectedEditorID: "MGRArniel01",
            selectedRow: makeJournalRow(
                editorID: "MGRArniel01", title: "Arniel's Endeavor",
                stage: 200, declaredStages: [10, 200], objectives: ["10 displayed"]
            ),
            selectedObjectives: ["10 Deliver ten cogs to Arniel Gane"],
            selectedLogEntries: ["Arniel Gane has asked for help."],
            lastOutcome: "MGRArniel01: started, stage none"
        )
        panel.provider = providers
        panel.loadViewIfNeeded()
        panel.questsSection.refreshReadout()

        let text = panel.questsSection.selectionReadout
        #expect(text.contains("Declared stages: 10, 200"))
        #expect(text.contains("Deliver ten cogs to Arniel Gane"))
        #expect(text.contains("Arniel Gane has asked for help."))
        #expect(text.contains("Last action: MGRArniel01: started"))
    }

    /// The alias readout is the Scripts panel's, on the quest selected here, so
    /// the two surfaces cannot describe the same #183 table differently.
    @Test @MainActor
    func aliasReadoutReusesTheScriptsAliasTable() {
        let panel = JournalPanelViewController()
        let providers = FakeWorldProviders()
        providers.journal.journalSnapshot = makeJournalSnapshot(
            selectedEditorID: "MGRArniel01"
        )
        providers.journal.aliasTables["MGRArniel01"] = ScriptQuestAliasInspection(
            editorID: "MGRArniel01",
            formIDText: "0006A086",
            isRunning: true,
            rows: [
                ScriptQuestAliasRow(
                    aliasID: 0, name: "ArnielGane", fillType: "specific reference",
                    isOptional: false, reference: "Skyrim.esm:0001C1B8"
                )
            ]
        )
        panel.provider = providers
        panel.loadViewIfNeeded()
        panel.questsSection.refreshReadout()

        let text = panel.questsSection.aliasReadout
        #expect(text.contains("MGRArniel01 (0006A086)"))
        #expect(text.contains("filled 1/1"))
        #expect(text.contains("[0] ArnielGane (specific reference) -> Skyrim.esm:0001C1B8"))
    }

    /// The gate tallies are stated even at zero: "0 faults" is the gate
    /// passing, and hiding it would look like a missing readout.
    @Test @MainActor
    func pageReadoutStatesTheStackTheRowsAndTheTallies() {
        let panel = JournalPanelViewController()
        let providers = FakeWorldProviders()
        providers.journal.journalSnapshot = makeJournalSnapshot(
            isOpen: true,
            openMenus: ["Journal"],
            listedQuestCount: 151,
            selectedIndex: 105,
            movieLoaded: true,
            movieQuestRows: 151,
            movieObjectiveRows: 1,
            movieTitleText: "Arniel's Endeavor",
            movieObjectiveFrames: ["Completed"]
        )
        panel.provider = providers
        panel.loadViewIfNeeded()
        panel.pageSection.refreshReadout()

        let text = panel.pageSection.readout
        #expect(text.contains("Journal: open"))
        #expect(text.contains("Menu stack: Journal"))
        #expect(text.contains("Listing: active quests  151 rows  selection 105"))
        #expect(text.contains("Movie rows: 151 quests, 1 objectives"))
        #expect(text.contains("Movie title: Arniel's Endeavor"))
        #expect(text.contains("Objective frames: Completed"))
        #expect(text.contains("Faults: 0"))
        #expect(text.contains("Unhandled invokes: 0"))
    }

    @Test @MainActor
    func pageReadoutStatesAMovieThatDidNotLoad() {
        let panel = JournalPanelViewController()
        let providers = FakeWorldProviders()
        providers.journal.journalSnapshot = makeJournalSnapshot(
            isOpen: true, movieLoaded: false, movieError: "No game data located."
        )
        panel.provider = providers
        panel.loadViewIfNeeded()
        panel.pageSection.refreshReadout()

        #expect(panel.pageSection.readout.contains("Movie: No game data located."))
    }

    // MARK: - Provider round-trip

    @Test @MainActor
    func controlsDriveTheProvider() {
        let panel = JournalPanelViewController()
        let providers = FakeWorldProviders()
        panel.provider = providers
        panel.loadViewIfNeeded()

        panel.questControl.stringValue = "MGRArniel01"
        sendScriptsControl(panel.questControl)
        sendScriptsControl(panel.startControl)
        panel.stageControl.stringValue = "10"
        sendScriptsControl(panel.setStageControl)
        panel.controlsSection.objectiveControl.stringValue = "10"
        sendScriptsControl(panel.controlsSection.showObjectiveControl)
        sendScriptsControl(panel.controlsSection.hideObjectiveControl)
        sendScriptsControl(panel.stopControl)

        #expect(providers.journal.journalQuestEditorID == "MGRArniel01")
        #expect(providers.journal.mutations == [
            "start MGRArniel01", "stage 10", "objective 10 true", "objective 10 false",
            "stop MGRArniel01"
        ])
    }

    /// A field holding something that is not an index applies nothing: stage 0
    /// is a legal stage, so falling back to it would be a different action than
    /// the one asked for.
    @Test @MainActor
    func anUnusableStageFieldAppliesNothing() {
        let panel = JournalPanelViewController()
        let providers = FakeWorldProviders()
        panel.provider = providers
        panel.loadViewIfNeeded()

        panel.stageControl.stringValue = "not a number"
        sendScriptsControl(panel.setStageControl)
        #expect(providers.journal.mutations.isEmpty)
        #expect(panel.controlsSection.stageIndex == nil)
    }

    @Test @MainActor
    func pageControlsOpenCloseAndRouteInput() {
        let panel = JournalPanelViewController()
        let providers = FakeWorldProviders()
        panel.provider = providers
        panel.loadViewIfNeeded()

        sendScriptsControl(panel.openControl)
        sendScriptsControl(panel.pageSection.upControl)
        sendScriptsControl(panel.pageSection.downControl)
        sendScriptsControl(panel.pageSection.activateControl)
        panel.pageSection.completedControl.state = .on
        sendScriptsControl(panel.pageSection.completedControl)
        sendScriptsControl(panel.closeControl)

        #expect(providers.journal.openCount == 1)
        #expect(providers.journal.closeCount == 1)
        #expect(providers.journal.inputEvents == [
            .move(.up), .move(.down), .button(.accept)
        ])
        #expect(providers.journal.mutations == ["showsCompleted true"])
    }

    /// The quest picker's completion list follows the loaded plugins.
    @Test @MainActor
    func questPickerListsTheSessionsJournalQuests() {
        let panel = JournalPanelViewController()
        let providers = FakeWorldProviders()
        providers.journal.journalQuestEditorIDs = ["MGRArniel01", "MQ101"]
        panel.provider = providers
        panel.loadViewIfNeeded()
        panel.questsSection.syncControls()

        #expect(panel.questControl.numberOfItems == 2)
        #expect(panel.questControl.itemObjectValue(at: 0) as? String == "MGRArniel01")
    }
}
