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
}
