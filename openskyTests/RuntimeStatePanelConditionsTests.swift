// World > Runtime State > Conditions verification surface (issue #166, roadmap
// item 10.2.4): selecting a decoded condition list, evaluating it against the
// live context, and reading back the verdict, the per-condition reasons, and
// the session's `ConditionTally` counters.
//
// `make test-ui` is TCC-blocked on this machine (docs/tools/environment.md), so
// both readouts are read back through `runtimeStateReadout` by accessibility id,
// which is what pins the id contract.

import AppKit
@testable import opensky
import Testing

struct RuntimeStatePanelConditionsTests {
    @Test @MainActor
    func accessibilityIdentifiersArePinned() {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        #expect(panel.conditionsSection.sectionIdentifier == "runtimeStateConditions")
        #expect(
            panel.runtimeStateConditionSourceControl.accessibilityIdentifier()
                == "RuntimeStateConditionSourceControl"
        )
        #expect(
            panel.runtimeStateConditionEvaluateControl.accessibilityIdentifier()
                == "RuntimeStateConditionEvaluateControl"
        )
        #expect(runtimeStateReadout("RuntimeStateConditionStatsLabel", in: panel.view) != nil)
        #expect(runtimeStateReadout("RuntimeStateConditionTallyStatsLabel", in: panel.view) != nil)
    }

    /// The verdict alone cannot distinguish "the world does not satisfy this"
    /// from "OpenSky cannot answer this yet", so the readout carries a reason
    /// per condition.
    @Test @MainActor
    func evaluateShowsTheVerdictAndEveryPerConditionReason() throws {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeRuntimeStateProvider()
        fake.runtimeStateConditionSources = ["MUSCombatTrack", "MUSDungeonTrack"]
        fake.conditionReports["MUSCombatTrack"] = Self.mixedReport
        panel.provider = fake

        panel.runtimeStateConditionSourceControl.stringValue = "MUSCombatTrack"
        sendRuntimeStateControl(panel.runtimeStateConditionEvaluateControl)

        #expect(fake.evaluatedSources == ["MUSCombatTrack"])
        let readout = try #require(
            runtimeStateReadout("RuntimeStateConditionStatsLabel", in: panel.view)
        )
        #expect(readout.contains("MUSCombatTrack: not satisfied (2 conditions)"))
        #expect(readout.contains("1. GetGlobalValue == 1 -> true [true]"))
        #expect(
            readout.contains("2. function 14095 == 1 -> false [unimplemented function 14095]")
        )
    }

    @Test @MainActor
    func tallyReadoutShowsTheSessionCounters() throws {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeRuntimeStateProvider()
        fake.runtimeStateConditionSources = ["MUSCombatTrack"]
        fake.conditionReports["MUSCombatTrack"] = Self.mixedReport
        panel.provider = fake
        panel.startInspecting()
        defer { panel.stopInspecting() }

        #expect(
            runtimeStateReadout("RuntimeStateConditionTallyStatsLabel", in: panel.view)
                == "Nothing evaluated yet."
        )

        panel.runtimeStateConditionSourceControl.stringValue = "MUSCombatTrack"
        sendRuntimeStateControl(panel.runtimeStateConditionEvaluateControl)
        let tally = try #require(
            runtimeStateReadout("RuntimeStateConditionTallyStatsLabel", in: panel.view)
        )
        #expect(tally.contains("Conditions evaluated: 2  Lists: 1"))
        #expect(tally.contains("Failures: 1"))
        #expect(tally.contains("Unimplemented: function 14095 x1"))
    }

    /// A satisfied list reads as satisfied, and an empty list is satisfied —
    /// which is what an unconditioned record means.
    @Test @MainActor
    func satisfiedAndEmptyListsReadAsSatisfied() throws {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeRuntimeStateProvider()
        fake.runtimeStateConditionSources = ["MUSQuiet"]
        fake.conditionReports["MUSQuiet"] = RuntimeStateConditionReport(
            source: "MUSQuiet", isSatisfied: true, lines: [],
            tallyLines: ["Conditions evaluated: 0  Lists: 1", "Failures: 0"]
        )
        panel.provider = fake

        panel.runtimeStateConditionSourceControl.stringValue = "MUSQuiet"
        sendRuntimeStateControl(panel.runtimeStateConditionEvaluateControl)
        let readout = try #require(
            runtimeStateReadout("RuntimeStateConditionStatsLabel", in: panel.view)
        )
        #expect(readout == "MUSQuiet: satisfied (0 conditions)")
    }

    /// No selection and an unknown name each read as a stated reason, never as
    /// a verdict about nothing.
    @Test @MainActor
    func emptyAndUnknownSourcesReadAsStatedConditions() throws {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeRuntimeStateProvider()
        fake.runtimeStateConditionSources = ["MUSCombatTrack"]
        panel.provider = fake

        sendRuntimeStateControl(panel.runtimeStateConditionEvaluateControl)
        #expect(fake.evaluatedSources.isEmpty)
        let unselected = try #require(
            runtimeStateReadout("RuntimeStateConditionStatsLabel", in: panel.view)
        )
        #expect(unselected == "Pick a condition list first.")

        panel.runtimeStateConditionSourceControl.stringValue = "MUSNotThere"
        sendRuntimeStateControl(panel.runtimeStateConditionEvaluateControl)
        let unknown = try #require(
            runtimeStateReadout("RuntimeStateConditionStatsLabel", in: panel.view)
        )
        #expect(unknown == "No condition list named MUSNotThere.")
    }

    @Test @MainActor
    func selectableSourcesComeFromTheProvider() {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeRuntimeStateProvider()
        fake.runtimeStateConditionSources = ["MUSCombatTrack", "MUSDungeonTrack"]
        panel.provider = fake
        #expect(panel.runtimeStateConditionSourceControl.objectValues as? [String]
            == ["MUSCombatTrack", "MUSDungeonTrack"])
    }

    /// Reading the world is not changing it, so this section never lights the
    /// override indicator.
    @Test @MainActor
    func evaluatingNeverMarksTheSectionOverridden() {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeRuntimeStateProvider()
        fake.runtimeStateConditionSources = ["MUSCombatTrack"]
        fake.conditionReports["MUSCombatTrack"] = Self.mixedReport
        panel.provider = fake
        panel.runtimeStateConditionSourceControl.stringValue = "MUSCombatTrack"
        sendRuntimeStateControl(panel.runtimeStateConditionEvaluateControl)
        #expect(!panel.conditionsSection.isOverridden)
    }

    // MARK: Synthetic engine state

    //
    // An invented report. `RuntimeStateConditionRunnerTests` covers the real
    // evaluation path against synthetic CTDA payloads; this suite only checks
    // that the panel renders whatever the provider hands it.

    private static let mixedReport = RuntimeStateConditionReport(
        source: "MUSCombatTrack",
        isSatisfied: false,
        lines: [
            RuntimeStateConditionLine(
                index: 1, text: "GetGlobalValue == 1", isTrue: true, reason: "true"
            ),
            RuntimeStateConditionLine(
                index: 2, text: "function 14095 == 1", isTrue: false,
                reason: "unimplemented function 14095"
            )
        ],
        tallyLines: [
            "Conditions evaluated: 2  Lists: 1",
            "Failures: 1",
            "Unimplemented: function 14095 x1"
        ]
    )
}
