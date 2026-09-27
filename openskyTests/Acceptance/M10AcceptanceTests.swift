// M10 milestone acceptance (issue #166), panel half. Drives the whole gate
// sentence for the M10.2 surfaces — scrub the game clock, mutate and reset a
// global, evaluate a decoded condition list, read the merged journal tail, and
// round-trip the session through a save slot — through the real shell types:
// the destination registry, the sidebar view controller, the registry's own
// panel factory, and the controls a user clicks. The only stand-in on this side
// is `FakeWorldProviders`, the same provider surface `GameViewController`
// implements.
//
// The suite has three satellites, split for the repo's file-length limit:
// `M10AcceptanceEngineTests.swift` runs the five-step round trip with no fakes
// at all (a real `WorldStateStore`, a real `GlobalStore`, a real `GameClock` and
// a real `OpenSkySaveStore`) and is where journal-independent snapshot equality
// is asserted; `M10AcceptanceWeatherTests.swift` proves weather and time stay
// synchronized at an elevated timescale; `M10AcceptanceRealDataTests.swift` is
// the env-gated check against the user's own install.
//
// `make test-ui` is blocked on the development machine (TCC harness init), so
// this unit-level test is the deterministic evidence for the gate. Readouts are
// read back by accessibility identifier out of the built view hierarchy, which
// also pins those identifiers as the UI-test contract. No game data is involved
// anywhere: every fixture below is invented in code.

import AppKit
import Foundation
@testable import opensky
import Testing

struct M10AcceptanceTests {
    // MARK: Step 1 — the destination carries the M10.2 sections

    /// Selecting World > Runtime State builds the panel through the registry
    /// factory and it carries the three sections M10.2 added, each with its
    /// section-header identifier and its readout on screen.
    @Test @MainActor
    func runtimeStateDestinationCarriesTheTimeGlobalsAndConditionSections() throws {
        let harness = M10AcceptanceHarness()
        let panel = try harness.selectRuntimeState()
        #expect(harness.selectedDestinationID == "runtimeState")

        #expect(panel.timeSection.sectionIdentifier == "runtimeStateTime")
        #expect(panel.globalsSection.sectionIdentifier == "runtimeStateGlobals")
        #expect(panel.conditionsSection.sectionIdentifier == "runtimeStateConditions")
        for identifier in Self.sectionHeaderIdentifiers {
            #expect(Self.hasIdentifier(identifier, in: panel.view), "missing \(identifier)")
        }
        for identifier in Self.readoutIdentifiers {
            #expect(harness.readout(identifier, in: panel) != nil, "missing \(identifier)")
        }
    }

    // MARK: Step 2 — scrub the clock and set the timescale

    /// The hour slider, the calendar fields and the timescale field all reach
    /// the engine, and `RuntimeStateTimeStatsLabel` renders the clock the engine
    /// answered with rather than what was typed at it.
    @Test @MainActor
    func scrubbingTheClockAndTimescaleReachesTheEngineAndTheReadout() throws {
        let harness = M10AcceptanceHarness()
        let panel = try harness.selectRuntimeState()
        try Self.scrubTheClock(harness, panel: panel)
    }

    // MARK: Step 3 — mutate and reset a global

    /// A global is written by editor ID, the readout states the plugin default
    /// beside the current value and says it is overridden, and Reset global puts
    /// it back and says so.
    @Test @MainActor
    func mutatingAndResettingAGlobalReachesTheEngineAndTheReadout() throws {
        let harness = M10AcceptanceHarness()
        Self.installGlobals(harness)
        let panel = try harness.selectRuntimeState()
        try Self.mutateAGlobal(harness, panel: panel)

        sendM10Control(panel.runtimeStateGlobalResetControl)
        harness.refresh(panel)
        #expect(harness.engine.globalResets == ["MyGold"])
        let readout = try #require(harness.readout("RuntimeStateGlobalsStatsLabel", in: panel))
        #expect(readout.contains("Reset MyGold to its plugin default."))
        #expect(readout.contains("default 100  current 100  at default"))
        #expect(readout.contains("Overridden: 0"))
    }

    // MARK: Step 4 — evaluate a condition list

    /// Evaluating a list reports the verdict, one line per condition with the
    /// reason that condition gave, and the session's tally counters in their own
    /// readout.
    @Test @MainActor
    func evaluatingAConditionListReportsVerdictReasonsAndTally() throws {
        let harness = M10AcceptanceHarness()
        Self.installConditions(harness)
        let panel = try harness.selectRuntimeState()
        try Self.evaluateConditions(harness, panel: panel)
    }

    // MARK: Step 5 — the journal tail carries the M10.2 mutations

    /// The tail readout interleaves reference writes, global writes and clock
    /// scrubs in one sequence-ordered log, which is what makes a clock scrub
    /// visible as the `GameHour` write it actually is.
    @Test @MainActor
    func theJournalTailShowsReferenceGlobalAndClockMutationsInOneLog() throws {
        let harness = M10AcceptanceHarness()
        let panel = try harness.selectRuntimeState(Self.mixedJournalSnapshot)
        let journal = try #require(harness.readout("RuntimeStateJournalStatsLabel", in: panel))
        #expect(journal == Self.mixedJournalSnapshot.journalTail.joined(separator: "\n"))
        #expect(journal.contains("11 set enableState skyrim.esm:000200"))
        #expect(journal.contains("12 set global MyGold = 2500"))
        #expect(journal.contains("13 set global GameHour = 7.25"))
        #expect(journal.contains("14 reset global MyGold"))

        let stats = try #require(harness.readout("RuntimeStateStatsLabel", in: panel))
        #expect(stats.contains("Next sequence: 15"))
        #expect(harness.readout("RuntimeStateResetStatsLabel", in: panel)?
            .contains("Overridden globals: 1") == true)
    }

    // MARK: Step 6 — the legacy Time of day slider still agrees with the clock

    /// The `TimeOfDayControl` under World > Environment predates the game clock
    /// and has to keep working: in the live app it writes
    /// `GameViewController.timeOfDay`, which is the very function
    /// `setGameClockHour(_:)` calls. Scrubbing it therefore moves the same clock
    /// the Runtime State panel reads, and both readouts show the same hour.
    @Test @MainActor
    func theLegacyTimeOfDaySliderMovesTheSameClockTheRuntimeStatePanelReads() throws {
        let harness = M10AcceptanceHarness()
        try Self.scrubTheLegacyTimeOfDaySlider(harness)
    }

    // MARK: The gate — one uninterrupted session

    /// The panel half of the M10 gate in one session, in the order a user
    /// performs it, on a single provider set: select World > Runtime State,
    /// mutate a reference, mutate a global, scrub the clock, evaluate a
    /// condition list, save the slot and load it back, then check the legacy
    /// Environment slider still agrees with the clock the session left behind.
    ///
    /// "Load into a fresh instance" is the one step a fake cannot prove, so the
    /// same five steps run against real engine objects in
    /// `M10AcceptanceEngineTests.swift`, which is where snapshot equality is
    /// asserted.
    @Test @MainActor
    func acceptanceFlowRunsEndToEndOnOneProviderSet() throws {
        let harness = M10AcceptanceHarness()
        Self.installGlobals(harness)
        Self.installConditions(harness)
        let panel = try harness.selectRuntimeState()
        #expect(harness.overrideIndicatorIsVisible("runtimeState") == false)

        panel.runtimeStateTargetControl.stringValue = "000200"
        sendM10Control(panel.runtimeStateDisableControl)
        #expect(harness.engine.enableCalls.map(\.enabled) == [false])

        try Self.mutateAGlobal(harness, panel: panel)
        try Self.scrubTheClock(harness, panel: panel)
        try Self.evaluateConditions(harness, panel: panel)

        // A written global and a non-vanilla timescale both light the sidebar.
        #expect(harness.overrideIndicatorIsVisible("runtimeState") == true)

        panel.runtimeStateSlotControl.stringValue = "m10-acceptance"
        sendM10Control(panel.runtimeStateSaveControl)
        sendM10Control(panel.runtimeStateLoadControl)
        harness.refresh(panel)
        #expect(harness.engine.savedSlots == ["m10-acceptance"])
        #expect(harness.engine.loadedSlots == ["m10-acceptance"])
        #expect(harness.readout("RuntimeStateSaveStatsLabel", in: panel)?
            .contains("Loaded m10-acceptance.") == true)

        try Self.scrubTheLegacyTimeOfDaySlider(harness)

        // The destination's own Reset all puts references, globals and the
        // timescale back to plugin data together.
        sendM10Control(panel.runtimeStateResetAllControl)
        harness.refresh(panel)
        #expect(harness.engine.resetAllGlobalsCount == 1)
        #expect(harness.engine.runtimeStateClock.timescale == GameClock.defaultTimescale)
        #expect(harness.overrideIndicatorIsVisible("runtimeState") == false)
    }

    // MARK: Shared step bodies

    /// Step 2, shared by the per-step test and the end-to-end run so both
    /// exercise identical code.
    @MainActor
    static func scrubTheClock(
        _ harness: M10AcceptanceHarness, panel: RuntimeStatePanelViewController
    ) throws {
        panel.runtimeStateHourControl.doubleValue = 7.25
        sendM10Control(panel.runtimeStateHourControl)
        #expect(harness.engine.hourCalls == [7.25])

        panel.runtimeStateDayControl.stringValue = "2"
        panel.runtimeStateMonthControl.selectItem(at: 11)
        panel.runtimeStateYearControl.stringValue = "202"
        sendM10Control(panel.runtimeStateApplyDateControl)
        #expect(harness.engine.dateCalls
            == [FakeRuntimeStateProvider.DateCall(day: 2, month: 12, year: 202)])

        panel.runtimeStateTimescaleControl.stringValue = "3600"
        sendM10Control(panel.runtimeStateApplyTimescaleControl)
        #expect(harness.engine.timescaleCalls == [3600])

        harness.refresh(panel)
        let readout = try #require(harness.readout("RuntimeStateTimeStatsLabel", in: panel))
        #expect(readout.contains("07:15  2 Evening Star, 4E 202"))
        #expect(readout.contains("Timescale: 3600"))
        #expect(readout.contains("World simulation: running"))
        // The controls resync from the engine's answer, not from the typed text.
        #expect(panel.runtimeStateTimescaleControl.stringValue == "3600")
        #expect(panel.runtimeStateDayControl.stringValue == "2")
    }

    /// Step 3's write half, shared with the end-to-end run.
    @MainActor
    static func mutateAGlobal(
        _ harness: M10AcceptanceHarness, panel: RuntimeStatePanelViewController
    ) throws {
        harness.refresh(panel)
        #expect(panel.runtimeStateGlobalControl.numberOfItems == 2)

        panel.runtimeStateGlobalControl.stringValue = "MyGold"
        panel.runtimeStateGlobalValueControl.stringValue = "2500"
        sendM10Control(panel.runtimeStateGlobalApplyControl)
        harness.refresh(panel)

        #expect(harness.engine.globalWrites.map(\.editorID) == ["MyGold"])
        #expect(harness.engine.globalWrites.map(\.value) == [2500])
        let readout = try #require(harness.readout("RuntimeStateGlobalsStatsLabel", in: panel))
        #expect(readout.contains("Globals loaded: 2  Overridden: 1"))
        #expect(readout.contains("MyGold (0000003A, short)"))
        #expect(readout.contains("default 100  current 2500  overridden"))
        #expect(readout.contains("Set MyGold to 2500."))
    }

    /// Step 4, shared with the end-to-end run.
    @MainActor
    static func evaluateConditions(
        _ harness: M10AcceptanceHarness, panel: RuntimeStatePanelViewController
    ) throws {
        harness.refresh(panel)
        panel.runtimeStateConditionSourceControl.stringValue = conditionSource
        sendM10Control(panel.runtimeStateConditionEvaluateControl)
        harness.refresh(panel)

        #expect(harness.engine.evaluatedSources == [conditionSource])
        let readout = try #require(harness.readout("RuntimeStateConditionStatsLabel", in: panel))
        #expect(readout.contains("\(Self.conditionSource): satisfied (2 conditions)"))
        #expect(readout.contains("1. GetGlobalValue MyGold >= 100 -> true [true]"))
        #expect(readout.contains("2. function 4154 == 1 -> false [unknownFunction(58)]"))

        let tally = try #require(
            harness.readout("RuntimeStateConditionTallyStatsLabel", in: panel)
        )
        #expect(tally.contains("Conditions evaluated: 2  Lists: 1"))
        #expect(tally.contains("Unknown functions: 1 (function 4154 x1)"))
    }

    /// Step 6, shared with the end-to-end run. Both readouts are read back by
    /// accessibility id, out of two separately built panels.
    @MainActor
    static func scrubTheLegacyTimeOfDaySlider(_ harness: M10AcceptanceHarness) throws {
        let environment = try #require(
            harness.select("environment") as? EnvironmentPanelViewController
        )
        let slider = environment.weatherSection.timeControl
        #expect(slider.accessibilityIdentifier() == "TimeOfDayControl")

        slider.doubleValue = 21.5
        sendM10Control(slider)
        harness.refresh(environment)
        #expect(harness.readout("TimeOfDayStatsLabel", in: environment) == "Time: 21:30")

        // The very same clock, read through the Runtime State destination.
        let panel = try #require(
            harness.select("runtimeState") as? RuntimeStatePanelViewController
        )
        #expect(harness.engine.runtimeStateClock.hourOfDay == 21.5)
        #expect(harness.readout("RuntimeStateTimeStatsLabel", in: panel)?
            .contains("21:30") == true)
    }

    // MARK: Synthetic engine state

    /// Section headers and readouts M10.2 added, pinned literally because they
    /// are the UI-test contract (docs/tools/app-ui.md).
    static let sectionHeaderIdentifiers = [
        "PanelSection-runtimeStateTime",
        "PanelSection-runtimeStateGlobals",
        "PanelSection-runtimeStateConditions"
    ]

    static let readoutIdentifiers = [
        "RuntimeStateTimeStatsLabel",
        "RuntimeStateGlobalsStatsLabel",
        "RuntimeStateConditionStatsLabel",
        "RuntimeStateConditionTallyStatsLabel"
    ]

    static let conditionSource = "MUSCombatBoss"

    /// Two invented globals: one ordinary short, one clock-owned. Both FormIDs
    /// and both values are made up; no plugin is read.
    @MainActor
    static func installGlobals(_ harness: M10AcceptanceHarness) {
        harness.engine.runtimeStateGlobalEditorIDs = ["GameHour", "MyGold"]
        harness.engine.globals = [
            "mygold": RuntimeStateGlobalSnapshot(
                editorID: "MyGold", formIDText: "0000003A", typeName: "short",
                defaultValue: 100, currentValue: 100, isOverridden: false, isConstant: false
            ),
            "gamehour": RuntimeStateGlobalSnapshot(
                editorID: "GameHour", formIDText: "00000038", typeName: "float",
                defaultValue: 13, currentValue: 13, isOverridden: false, isConstant: false
            )
        ]
    }

    /// One invented condition list: a satisfied global comparison OR-joined to a
    /// condition whose function the registry does not implement, so the report
    /// has to distinguish "false because the world says so" from "false because
    /// the engine cannot answer".
    @MainActor
    static func installConditions(_ harness: M10AcceptanceHarness) {
        harness.engine.runtimeStateConditionSources = [conditionSource]
        harness.engine.conditionReports[conditionSource] = RuntimeStateConditionReport(
            source: conditionSource,
            isSatisfied: true,
            lines: [
                RuntimeStateConditionLine(
                    index: 1, text: "GetGlobalValue MyGold >= 100", isTrue: true, reason: "true"
                ),
                RuntimeStateConditionLine(
                    index: 2, text: "function 4154 == 1", isTrue: false,
                    reason: "unknownFunction(58)"
                )
            ],
            tallyLines: [
                "Conditions evaluated: 2  Lists: 1",
                "Unknown functions: 1 (function 4154 x1)"
            ]
        )
    }

    /// What a session reports after a reference write, a global write, a clock
    /// scrub and a global reset: the two journal rings already interleaved by
    /// their shared sequence counter. Invented lines, no game data.
    static let mixedJournalSnapshot = RuntimeStateSnapshot(
        residentReferenceCount: 118,
        dirtyReferenceCount: 1,
        journalTail: [
            "11 set enableState skyrim.esm:000200",
            "12 set global MyGold = 2500",
            "13 set global GameHour = 7.25",
            "14 reset global MyGold"
        ],
        droppedJournalEntryCount: 0,
        nextJournalSequence: 15,
        currentTargetDescription: "skyrim.esm:000200",
        overriddenGlobalCount: 1
    )

    /// Depth-first search for any view carrying `identifier`, not just a label,
    /// because a section header is a button rather than a text field.
    @MainActor
    static func hasIdentifier(_ identifier: String, in view: NSView) -> Bool {
        if view.accessibilityIdentifier() == identifier {
            return true
        }
        return view.subviews.contains { hasIdentifier(identifier, in: $0) }
    }
}
