// M13 milestone panel acceptance (issue #185): one uninterrupted run through
// the real sidebar model and the registry-built World > Quests & Journal panel
// on a single provider set, in the M10/M11 acceptance-triad shape.
//
// The readouts are found by their accessibility identifiers, which is the
// deterministic substitute while UI automation is TCC-blocked
// (docs/tools/environment.md). `JournalPanelTests` covers each section on its
// own; what this adds is that the whole destination works as one surface, in
// the order a session would use it, without a single fake being swapped
// halfway.

import AppKit
@testable import opensky
import Testing

@MainActor
struct M13AcceptancePanelTests {
    /// The quest the run drives, spelled the way the real gate's target quest
    /// is so the readouts read like a session's.
    private static let editorID = "MGRArniel01"

    @Test
    func journalDestinationRunsTheWholeAcceptanceFlow() throws {
        let providers = FakeWorldProviders()
        providers.journal.journalQuestEditorIDs = [Self.editorID, "MQ101"]
        providers.journal.journalSnapshot = Self.advancedSnapshot()
        providers.journal.aliasTables[Self.editorID] = Self.aliasTable()

        let panel = try Self.buildPanel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        Self.expectReadouts(panel)
        Self.driveTheQuest(panel, providers: providers)
        try Self.openAndCloseThePage(panel, providers: providers)
    }

    // MARK: - The run

    /// The sidebar row and the registry factory, taken through the same path
    /// the app takes rather than by constructing the panel directly.
    private static func buildPanel(
        providers: FakeWorldProviders
    ) throws -> JournalPanelViewController {
        let worldGroup = try #require(
            AppSidebarModel.groups().first { $0.section == .world }
        )
        let descriptor = try #require(
            worldGroup.destinations.first { $0.id == "journal" }
        )
        #expect(descriptor.sidebarIdentifier == "Destination-journal")
        #expect(descriptor.title == "Quests & Journal")

        guard case let .worldInspector(makePanel) = descriptor.content else {
            Issue.record("World > Quests & Journal is not a world inspector")
            throw M13PanelAcceptanceError.notAWorldInspector
        }
        let panel = try #require(
            makePanel(WorldPanelContext(providers: providers)) as? JournalPanelViewController
        )
        panel.loadViewIfNeeded()
        return panel
    }

    /// Every readout the destination publishes, read back by accessibility id.
    /// A quest that is running with a stage reached, an objective on the page
    /// and a journal paragraph under it has to be visible in all four.
    private static func expectReadouts(_ panel: JournalPanelViewController) {
        #expect(scriptsReadout("JournalQuestsStatsLabel", in: panel.view)?
            .contains("\(editorID) \"Arniel's Endeavor\"") == true)
        #expect(scriptsReadout("JournalSelectionStatsLabel", in: panel.view)?
            .contains("Deliver ten cogs to Arniel Gane") == true)
        #expect(scriptsReadout("JournalSelectionStatsLabel", in: panel.view)?
            .contains("Arniel Gane has asked for help.") == true)
        #expect(scriptsReadout("JournalAliasStatsLabel", in: panel.view)?
            .contains("[0] ArnielGane (specific reference)") == true)
        #expect(scriptsReadout("JournalControlsStatsLabel", in: panel.view)?
            .contains("Last action: \(editorID): stage 10") == true)
        #expect(scriptsReadout("JournalPageStatsLabel", in: panel.view)?
            .contains("Journal: closed") == true)
    }

    /// The quest transport, in the order the milestone's loop uses it: pick a
    /// quest, start it, set the stage the lever would set, show the objective
    /// the fragment would show, hide it again, stop.
    private static func driveTheQuest(
        _ panel: JournalPanelViewController,
        providers: FakeWorldProviders
    ) {
        panel.questControl.stringValue = editorID
        sendScriptsControl(panel.questControl)
        sendScriptsControl(panel.startControl)
        panel.stageControl.stringValue = "10"
        sendScriptsControl(panel.setStageControl)
        panel.controlsSection.objectiveControl.stringValue = "10"
        sendScriptsControl(panel.controlsSection.showObjectiveControl)
        sendScriptsControl(panel.controlsSection.hideObjectiveControl)
        sendScriptsControl(panel.stopControl)

        #expect(providers.journal.journalQuestEditorID == editorID)
        #expect(providers.journal.mutations == [
            "start \(editorID)", "stage 10", "objective 10 true", "objective 10 false",
            "stop \(editorID)"
        ])
    }

    /// The page half, and the destination's override policy with it: an open
    /// journal is the override, driving a quest is not, and the sidebar's reset
    /// closes the page without undoing a single quest mutation.
    private static func openAndCloseThePage(
        _ panel: JournalPanelViewController,
        providers: FakeWorldProviders
    ) throws {
        let descriptor = try #require(DestinationRegistry.destination(id: "journal"))
        let context = WorldPanelContext(providers: providers)
        let overrides = try #require(descriptor.overrides)
        #expect(!overrides.isOverridden(context), "driving a quest must not light the dot")

        sendScriptsControl(panel.openControl)
        #expect(overrides.isOverridden(context))
        panel.startInspecting()
        #expect(scriptsReadout("JournalPageStatsLabel", in: panel.view)?
            .contains("Journal: open") == true)

        sendScriptsControl(panel.pageSection.upControl)
        sendScriptsControl(panel.pageSection.downControl)
        sendScriptsControl(panel.pageSection.activateControl)
        panel.pageSection.completedControl.state = .on
        sendScriptsControl(panel.pageSection.completedControl)
        #expect(providers.journal.inputEvents == [
            .move(.up), .move(.down), .button(.accept)
        ])
        #expect(providers.journal.mutations.last == "showsCompleted true")

        // The sidebar's own reset, not the panel's Close button: it is the
        // registry contract that has to put the page away.
        overrides.resetToDefaults(context)
        #expect(!overrides.isOverridden(context))
        panel.startInspecting()
        #expect(scriptsReadout("JournalPageStatsLabel", in: panel.view)?
            .contains("Journal: closed") == true)
        #expect(providers.journal.closeCount == 1)
        // The quest mutations survived the reset, which is the whole point of
        // keeping world state out of the override.
        #expect(providers.journal.mutations.contains("start \(editorID)"))
    }

    // MARK: - Fixtures

    /// The session the readouts describe: one quest running at stage 10 with
    /// its objective displayed and its first journal paragraph written.
    private static func advancedSnapshot() -> JournalControlSnapshot {
        makeJournalSnapshot(
            questCount: 400,
            runningCount: 1,
            completedCount: 0,
            rows: [makeJournalRow(
                editorID: editorID,
                title: "Arniel's Endeavor",
                kind: "mages guild",
                stage: 10,
                declaredStages: [10, 200],
                objectives: ["10 displayed"]
            )],
            selectedEditorID: editorID,
            selectedRow: makeJournalRow(
                editorID: editorID,
                title: "Arniel's Endeavor",
                kind: "mages guild",
                stage: 10,
                declaredStages: [10, 200],
                objectives: ["10 displayed"]
            ),
            selectedObjectives: ["10 Deliver ten cogs to Arniel Gane"],
            selectedLogEntries: ["Arniel Gane has asked for help."],
            lastOutcome: "\(editorID): stage 10",
            listedQuestCount: 1,
            selectedIndex: 0
        )
    }

    private static func aliasTable() -> ScriptQuestAliasInspection {
        ScriptQuestAliasInspection(
            editorID: editorID,
            formIDText: "0006A086",
            isRunning: true,
            rows: [ScriptQuestAliasRow(
                aliasID: 0,
                name: "ArnielGane",
                fillType: "specific reference",
                isOptional: false,
                reference: "Skyrim.esm:0001C1B8"
            )]
        )
    }
}

/// Thrown only to end the run early when the registry hands back something
/// other than a world inspector, which `Issue.record` has already reported.
private enum M13PanelAcceptanceError: Error {
    case notAWorldInspector
}
