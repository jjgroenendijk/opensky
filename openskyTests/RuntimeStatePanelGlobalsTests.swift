// World > Runtime State > Globals verification surface (issue #166, roadmap
// item 10.2.2): looking a global up by editor ID, seeing the plugin default
// beside the runtime value and whether it is overridden, writing it, and
// resetting it.
//
// `make test-ui` is TCC-blocked on this machine (docs/tools/environment.md), so
// every readout here is read back through `runtimeStateReadout` by accessibility
// id. That is what pins the id contract.

import AppKit
@testable import opensky
import Testing

struct RuntimeStatePanelGlobalsTests {
    @Test @MainActor
    func accessibilityIdentifiersArePinned() {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        #expect(panel.globalsSection.sectionIdentifier == "runtimeStateGlobals")
        #expect(
            panel.runtimeStateGlobalControl.accessibilityIdentifier()
                == "RuntimeStateGlobalControl"
        )
        #expect(
            panel.runtimeStateGlobalValueControl.accessibilityIdentifier()
                == "RuntimeStateGlobalValueControl"
        )
        #expect(
            panel.runtimeStateGlobalApplyControl.accessibilityIdentifier()
                == "RuntimeStateGlobalApplyControl"
        )
        #expect(
            panel.runtimeStateGlobalResetControl.accessibilityIdentifier()
                == "RuntimeStateGlobalResetControl"
        )
        #expect(runtimeStateReadout("RuntimeStateGlobalsStatsLabel", in: panel.view) != nil)
    }

    /// Default, current value and overridden-ness are three separate facts and
    /// the readout states all three.
    @Test @MainActor
    func readoutShowsPluginDefaultBesideRuntimeValueAndOverrideState() throws {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = Self.providerWithTimeScale()
        panel.provider = fake
        panel.startInspecting()
        defer { panel.stopInspecting() }

        panel.runtimeStateGlobalControl.stringValue = "TimeScale"
        panel.globalsSection.refreshReadout()
        let readout = try #require(
            runtimeStateReadout("RuntimeStateGlobalsStatsLabel", in: panel.view)
        )
        #expect(readout.contains("Globals loaded: 2"))
        #expect(readout.contains("Overridden: 0"))
        #expect(readout.contains("TimeScale (0000003A, short)"))
        #expect(readout.contains("default 20"))
        #expect(readout.contains("current 20"))
        #expect(readout.contains("at default"))
    }

    @Test @MainActor
    func writingAGlobalReachesTheProviderAndReadsBackAsOverridden() throws {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = Self.providerWithTimeScale()
        panel.provider = fake

        panel.runtimeStateGlobalControl.stringValue = "TimeScale"
        panel.runtimeStateGlobalValueControl.stringValue = "120"
        sendRuntimeStateControl(panel.runtimeStateGlobalApplyControl)

        #expect(fake.globalWrites.map(\.editorID) == ["TimeScale"])
        #expect(fake.globalWrites.map(\.value) == [120])
        let readout = try #require(
            runtimeStateReadout("RuntimeStateGlobalsStatsLabel", in: panel.view)
        )
        #expect(readout.contains("Set TimeScale to 120."))
        #expect(readout.contains("current 120"))
        #expect(readout.contains("overridden"))
        #expect(readout.contains("Overridden: 1"))
    }

    @Test @MainActor
    func resettingAGlobalRestoresThePluginDefault() throws {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = Self.providerWithTimeScale()
        panel.provider = fake

        panel.runtimeStateGlobalControl.stringValue = "TimeScale"
        panel.runtimeStateGlobalValueControl.stringValue = "120"
        sendRuntimeStateControl(panel.runtimeStateGlobalApplyControl)
        sendRuntimeStateControl(panel.runtimeStateGlobalResetControl)

        #expect(fake.globalResets == ["TimeScale"])
        let readout = try #require(
            runtimeStateReadout("RuntimeStateGlobalsStatsLabel", in: panel.view)
        )
        #expect(readout.contains("Reset TimeScale to its plugin default."))
        #expect(readout.contains("current 20"))
        #expect(readout.contains("at default"))

        // Resetting again has nothing to do, and says so.
        sendRuntimeStateControl(panel.runtimeStateGlobalResetControl)
        let second = try #require(
            runtimeStateReadout("RuntimeStateGlobalsStatsLabel", in: panel.view)
        )
        #expect(second.contains("Nothing to reset for TimeScale."))
    }

    /// Editor-ID matching is case-insensitive, exactly as `GlobalStore` matches.
    @Test @MainActor
    func lookupIsCaseInsensitive() throws {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        // Held in a local: `provider` is weak.
        let fake = Self.providerWithTimeScale()
        panel.provider = fake

        panel.runtimeStateGlobalControl.stringValue = "timescale"
        panel.globalsSection.refreshReadout()
        let readout = try #require(
            runtimeStateReadout("RuntimeStateGlobalsStatsLabel", in: panel.view)
        )
        #expect(readout.contains("TimeScale (0000003A, short)"))
    }

    /// A name nothing defines, an empty selection and a non-numeric value each
    /// read as a stated condition rather than as a blank or a silent no-op.
    @Test @MainActor
    func unknownEmptyAndNonNumericEntriesReadAsStatedConditions() throws {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = Self.providerWithTimeScale()
        panel.provider = fake

        panel.globalsSection.refreshReadout()
        let empty = try #require(
            runtimeStateReadout("RuntimeStateGlobalsStatsLabel", in: panel.view)
        )
        #expect(empty.contains("No global selected."))

        sendRuntimeStateControl(panel.runtimeStateGlobalApplyControl)
        #expect(fake.globalWrites.isEmpty)
        let unselected = try #require(
            runtimeStateReadout("RuntimeStateGlobalsStatsLabel", in: panel.view)
        )
        #expect(unselected.contains("Pick a global first."))

        panel.runtimeStateGlobalControl.stringValue = "NotAGlobal"
        panel.runtimeStateGlobalValueControl.stringValue = "1"
        sendRuntimeStateControl(panel.runtimeStateGlobalApplyControl)
        let unknown = try #require(
            runtimeStateReadout("RuntimeStateGlobalsStatsLabel", in: panel.view)
        )
        #expect(unknown.contains("No loaded plugin defines NotAGlobal."))
        #expect(unknown.contains("No write applied to NotAGlobal."))

        panel.runtimeStateGlobalControl.stringValue = "TimeScale"
        panel.runtimeStateGlobalValueControl.stringValue = "quickly"
        sendRuntimeStateControl(panel.runtimeStateGlobalApplyControl)
        let nonNumeric = try #require(
            runtimeStateReadout("RuntimeStateGlobalsStatsLabel", in: panel.view)
        )
        #expect(nonNumeric.contains("Value must be a number."))
    }

    /// Selecting a global loads its current value into the field, so the Set
    /// button starts from what the world holds rather than from stale text.
    @Test @MainActor
    func selectingAGlobalLoadsItsCurrentValue() {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        // Held in a local: `provider` is weak.
        let fake = Self.providerWithTimeScale()
        panel.provider = fake

        panel.runtimeStateGlobalControl.stringValue = "PlayerGold"
        sendRuntimeStateControl(panel.runtimeStateGlobalControl)
        #expect(panel.runtimeStateGlobalValueControl.stringValue == "750")
    }

    /// The completion list comes from the loaded plugins.
    @Test @MainActor
    func completionListHoldsEveryLoadedEditorID() {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        // Held in a local: `provider` is weak.
        let fake = Self.providerWithTimeScale()
        panel.provider = fake
        panel.globalsSection.syncControls()
        #expect(panel.runtimeStateGlobalControl.objectValues as? [String]
            == ["PlayerGold", "TimeScale"])
    }

    @Test @MainActor
    func sectionOverrideTracksTheOverriddenGlobalCount() {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = Self.providerWithTimeScale()
        panel.provider = fake
        #expect(!panel.globalsSection.isOverridden)

        fake.setGlobalValue(120, editorID: "TimeScale")
        #expect(panel.globalsSection.isOverridden)

        panel.globalsSection.performResetToDefaults()
        #expect(fake.resetAllGlobalsCount == 1)
        #expect(!panel.globalsSection.isOverridden)
    }

    // MARK: Synthetic engine state

    //
    // Invented GLOB records. The FormIDs and values are made up for this test;
    // nothing is read from a game file.

    @MainActor
    private static func providerWithTimeScale() -> FakeRuntimeStateProvider {
        let fake = FakeRuntimeStateProvider()
        fake.runtimeStateGlobalEditorIDs = ["PlayerGold", "TimeScale"]
        fake.globals = [
            "timescale": RuntimeStateGlobalSnapshot(
                editorID: "TimeScale", formIDText: "0000003A", typeName: "short",
                defaultValue: 20, currentValue: 20, isOverridden: false, isConstant: false
            ),
            "playergold": RuntimeStateGlobalSnapshot(
                editorID: "PlayerGold", formIDText: "0000003B", typeName: "long",
                defaultValue: 750, currentValue: 750, isOverridden: false, isConstant: false
            )
        ]
        return fake
    }
}
