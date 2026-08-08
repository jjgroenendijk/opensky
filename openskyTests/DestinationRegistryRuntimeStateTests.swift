// Satellite of DestinationRegistryTests (M10.1.5): the World > Runtime State
// destination's slice of the registry contract. Split out because the parent
// file sits at the length limit, and because this is the one destination whose
// overridden-ness is world state rather than a panel setting.

import AppKit
@testable import opensky
import Testing

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
