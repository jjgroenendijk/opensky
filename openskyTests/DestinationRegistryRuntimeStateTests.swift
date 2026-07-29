// Satellite of DestinationRegistryTests (M10.1.5): the World > Runtime State
// destination's slice of the registry contract. Split out because the parent
// file sits at the length limit, and because this is the one destination whose
// overridden-ness is world state rather than a panel setting.

import AppKit
@testable import opensky
import Testing

/// Forwards the runtime-state seam to the panel tests' recorder rather than
/// duplicating it, so a registry-level reset and a panel-level button press are
/// observed through the same fake. The conformance itself comes from
/// `WorldControlProviders`, which the class already declares; restating it here
/// would be redundant.
extension FakeWorldProviders {
    var runtimeStateSnapshot: RuntimeStateSnapshot {
        runtimeState.runtimeStateSnapshot
    }

    var lastSaveOutcome: RuntimeStateSaveOutcome {
        runtimeState.lastSaveOutcome
    }

    var runtimeStateSaveSlots: [String] {
        runtimeState.runtimeStateSaveSlots
    }

    @discardableResult
    func setReferenceEnabled(_ enabled: Bool, target: RuntimeStateTargetSelector) -> Bool {
        runtimeState.setReferenceEnabled(enabled, target: target)
    }

    @discardableResult
    func nudgeReferenceTransform(target: RuntimeStateTargetSelector) -> Bool {
        runtimeState.nudgeReferenceTransform(target: target)
    }

    @discardableResult
    func resetReferenceState(target: RuntimeStateTargetSelector) -> Bool {
        runtimeState.resetReferenceState(target: target)
    }

    func resetAllReferenceState() {
        runtimeState.resetAllReferenceState()
    }

    func saveWorldState(slot: String) {
        runtimeState.saveWorldState(slot: slot)
    }

    func loadWorldState(slot: String) {
        runtimeState.loadWorldState(slot: slot)
    }

    var runtimeStateClock: RuntimeStateClockSnapshot {
        runtimeState.runtimeStateClock
    }

    /// The legacy `TimeOfDayControl` under World > Environment writes this
    /// property, and `GameViewController.timeOfDay` and
    /// `GameViewController.setGameClockHour(_:)` are literally the same write in
    /// the live app — the latter calls the former. Forwarding here rather than
    /// storing a second float is what lets the M10 gate assert that the two
    /// surfaces agree instead of asserting it about a fake that cannot disagree.
    var timeOfDay: Float {
        get { runtimeState.runtimeStateClock.hourOfDay }
        set { runtimeState.setGameClockHour(newValue) }
    }

    func setGameClockHour(_ hour: Float) {
        runtimeState.setGameClockHour(hour)
    }

    func setGameClockDate(day: Int, month: Int, year: Int) {
        runtimeState.setGameClockDate(day: day, month: month, year: year)
    }

    @discardableResult
    func setGameTimescale(_ timescale: Float) -> Bool {
        runtimeState.setGameTimescale(timescale)
    }

    var runtimeStateGlobalEditorIDs: [String] {
        runtimeState.runtimeStateGlobalEditorIDs
    }

    func runtimeStateGlobal(editorID: String) -> RuntimeStateGlobalSnapshot? {
        runtimeState.runtimeStateGlobal(editorID: editorID)
    }

    @discardableResult
    func setGlobalValue(_ value: Float, editorID: String) -> Bool {
        runtimeState.setGlobalValue(value, editorID: editorID)
    }

    @discardableResult
    func resetGlobalValue(editorID: String) -> Bool {
        runtimeState.resetGlobalValue(editorID: editorID)
    }

    func resetAllGlobalOverrides() {
        runtimeState.resetAllGlobalOverrides()
    }

    var runtimeStateConditionSources: [String] {
        runtimeState.runtimeStateConditionSources
    }

    func evaluateConditions(source: String) -> RuntimeStateConditionReport {
        runtimeState.evaluateConditions(source: source)
    }
}

struct DestinationRegistryRuntimeStateTests {
    /// A dirty reference is what "overridden" means for this destination —
    /// plugin data is the default — and the sidebar's reset drops every delta.
    /// A fresh session has none, which the parent suite's all-destinations
    /// sweep also relies on.
    @Test @MainActor
    func runtimeStateOverrideTracksDirtyReferencesAndResetsThemAll() throws {
        let providers = FakeWorldProviders()
        let context = WorldPanelContext(providers: providers)
        let overrides = try #require(
            DestinationRegistry.destination(id: "runtimeState")?.overrides
        )
        #expect(!overrides.isOverridden(context))

        providers.runtimeState.runtimeStateSnapshot = RuntimeStateSnapshot(
            residentReferenceCount: 120,
            dirtyReferenceCount: 4,
            journalTail: ["1 set enableState skyrim.esm:00003F"],
            droppedJournalEntryCount: 0,
            nextJournalSequence: 2,
            currentTargetDescription: "skyrim.esm:00003F"
        )
        #expect(overrides.isOverridden(context))

        overrides.resetToDefaults(context)
        #expect(providers.runtimeState.resetAllCount == 1)
        #expect(!overrides.isOverridden(context))
        // Reset drops deltas; it never touches the resident cells themselves.
        #expect(providers.runtimeStateSnapshot.residentReferenceCount == 120)
    }

    /// The destination dot is the union of everything under Runtime State that
    /// can sit away from plugin data (issue #166): dirty references, overridden
    /// globals, and a timescale off the vanilla default. Each is asserted on its
    /// own so a future change cannot quietly drop one from the union.
    @Test @MainActor
    func destinationOverrideCoversGlobalsAndTimescaleAsWellAsReferences() throws {
        let providers = FakeWorldProviders()
        let context = WorldPanelContext(providers: providers)
        let overrides = try #require(
            DestinationRegistry.destination(id: "runtimeState")?.overrides
        )
        #expect(!overrides.isOverridden(context))

        providers.runtimeState.globals["mygold"] = RuntimeStateGlobalSnapshot(
            editorID: "MyGold", formIDText: "0000003A", typeName: "short",
            defaultValue: 0, currentValue: 0, isOverridden: false, isConstant: false
        )
        providers.runtimeState.setGlobalValue(25, editorID: "MyGold")
        #expect(overrides.isOverridden(context))

        providers.runtimeState.resetAllGlobalOverrides()
        #expect(!overrides.isOverridden(context))

        providers.runtimeState.setGameTimescale(200)
        #expect(overrides.isOverridden(context))

        overrides.resetToDefaults(context)
        #expect(!overrides.isOverridden(context))
        #expect(providers.runtimeState.runtimeStateClock.timescale == GameClock.defaultTimescale)
        #expect(providers.runtimeState.resetAllGlobalsCount == 2)
    }
}
