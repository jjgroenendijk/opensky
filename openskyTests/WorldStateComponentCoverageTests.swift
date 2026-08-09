// Every-component-kind coverage for `WorldStateStore` (issues #159, #176,
// #177, #194, #197, #374, #426). Split from `WorldStateStoreTests`, which sits at the strict-lint
// type-length cap, and kept together because these two tests are the ones that
// have to be updated whenever a component kind is added: both assert against
// `WorldStateComponentKind.allCases`, so a new kind fails here until it is
// storable, readable and resettable.

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct WorldStateComponentCoverageTests {
    private let whiterun = CellSceneLocation.exterior(CellCoordinate(x: 5, y: -1))

    private func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: "skyrim.esm", objectID: objectID)
    }

    private func transform(_ x: Float) -> ReferenceTransformOverride {
        ReferenceTransformOverride(position: SIMD3(x, 0, 0), scale: 1)
    }

    /// One dropped object. Nothing stops a plugin reference carrying a spawn
    /// component — the store is generic over kinds — so these fixtures reuse
    /// one key for all six.
    private var spawn: ReferenceSpawnState {
        ReferenceSpawnState(
            base: FormID(0x100),
            location: whiterun,
            placement: PlacedReference.Placement(position: SIMD3(7, 8, 9), rotation: .zero)
        )
    }

    /// One started quest, stage 10 reached.
    private var questState: QuestRuntimeState {
        QuestRuntimeState(isRunning: true, stagesReached: [10])
    }

    /// That quest's one filled alias.
    private var questAliases: QuestAliasState {
        QuestAliasState(fills: [QuestAliasFill(aliasID: 1, reference: key(0x300))])
    }

    /// One wounded actor.
    private var actorValues: ActorValueState {
        ActorValueState(current: ActorValues(health: 42, magicka: 7, stamina: 13))
    }

    /// One corpse, settled where it fell.
    private var death: ActorDeathState {
        ActorDeathState.justDied.settled(
            at: SIMD3(10, 20, 30), orientation: .identityRotation
        )
    }

    @Test func storesAndReadsBackEveryComponentKind() {
        let store = WorldStateStore()
        let reference = key(0x200)
        #expect(store.set(ReferenceEnableState.disabled, for: reference, in: whiterun))
        #expect(store.set(transform(9), for: reference, in: whiterun))
        #expect(store.set(
            ReferenceActivationState(activationCount: 2, isOpen: true, lastActivator: key(0x14)),
            for: reference,
            in: whiterun
        ))
        #expect(store.set(ReferenceDeletionState.deleted, for: reference, in: whiterun))
        // An emptied container: the fifth component kind, stored. What the
        // component itself can hold is InventoryComponentTests' subject.
        #expect(store.set(ReferenceInventoryState.empty, for: reference, in: whiterun))
        // A dropped object: the sixth kind, whose own subject is
        // SpawnedReferenceTests. Nothing stops a plugin reference carrying one
        // — the store is generic over kinds — so the fixture reuses this key.
        #expect(store.set(spawn, for: reference, in: whiterun))
        // A started quest: the seventh kind, whose own subject is
        // QuestRuntimeTests. A quest is normally keyed by a QUST record rather
        // than by a placement, which the store likewise does not care about.
        #expect(store.set(questState, for: reference, in: whiterun))
        // That quest's filled aliases: the eighth kind, whose own subject is
        // QuestAliasTests. It is keyed by the same QUST record the seventh is.
        #expect(store.set(questAliases, for: reference, in: whiterun))
        // A wounded actor: the ninth kind, whose own subject is
        // ActorValueRuntimeTests.
        #expect(store.set(actorValues, for: reference, in: whiterun))
        // A dead actor: the tenth kind, whose own subject is
        // RagdollRuntimeTests.
        #expect(store.set(death, for: reference, in: whiterun))
        // An angry actor: the eleventh kind, whose own subject is
        // CombatLoopRuntimeTests.
        #expect(store.set(ActorCombatState.hostile, for: reference, in: whiterun))
        // A spoken response: the twelfth kind, whose own subject is
        // DialogueRuntimeTests. It is keyed by an INFO record rather than by a
        // placement, which the store likewise does not care about.
        #expect(store.set(DialogueRuntimeState(saidCount: 1), for: reference, in: whiterun))

        #expect(store.component(ReferenceEnableState.self, for: reference)?.isEnabled == false)
        #expect(store.component(ReferenceTransformOverride.self, for: reference) == transform(9))
        let activation = store.component(ReferenceActivationState.self, for: reference)
        #expect(activation?.activationCount == 2)
        #expect(activation?.isOpen == true)
        #expect(activation?.lastActivator == key(0x14))
        #expect(store.component(ReferenceDeletionState.self, for: reference)?.isDeleted == true)
        #expect(store.component(ReferenceInventoryState.self, for: reference) == .empty)
        #expect(store.component(ReferenceSpawnState.self, for: reference) == spawn)
        #expect(store.component(QuestRuntimeState.self, for: reference) == questState)
        #expect(store.component(QuestAliasState.self, for: reference) == questAliases)
        #expect(store.component(ActorValueState.self, for: reference) == actorValues)
        #expect(store.component(ActorDeathState.self, for: reference) == death)
        #expect(store.component(ActorCombatState.self, for: reference) == .hostile)
        #expect(store.component(DialogueRuntimeState.self, for: reference)?.saidCount == 1)
        #expect(store.delta(for: reference)?.sortedKinds == WorldStateComponentKind.allCases)
    }

    @Test func wholesaleResetDropsEveryComponent() {
        let store = WorldStateStore()
        let reference = key(0x200)
        store.set(ReferenceEnableState.disabled, for: reference, in: whiterun)
        store.set(transform(3), for: reference, in: whiterun)
        store.set(ReferenceActivationState(activationCount: 1), for: reference, in: whiterun)
        store.set(ReferenceDeletionState.deleted, for: reference, in: whiterun)
        store.set(ReferenceInventoryState.empty, for: reference, in: whiterun)
        store.set(spawn, for: reference, in: whiterun)
        store.set(questState, for: reference, in: whiterun)
        store.set(questAliases, for: reference, in: whiterun)
        store.set(actorValues, for: reference, in: whiterun)
        store.set(death, for: reference, in: whiterun)
        store.set(ActorCombatState.hostile, for: reference, in: whiterun)
        store.set(DialogueRuntimeState(saidCount: 1), for: reference, in: whiterun)
        #expect(store.reset(reference))
        #expect(store.delta(for: reference) == nil)
        #expect(store.dirtyCount == 0)
        // One journal entry per cleared component, in allCases order.
        let resets = store.journalEntries.filter(\.isReset)
        #expect(resets.map(\.kind) == WorldStateComponentKind.allCases)
    }
}
