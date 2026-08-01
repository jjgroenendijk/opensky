// World item take/drop/container tests (issue #177, roadmap item 12.1.3).
//
// Everything runs on a real `WorldStateStore` and a real `InventoryRuntime`
// over the synthetic M12.1 plugin, with `PapyrusWorldFixtureReferences` in
// place of a `CellStreamer` so no scene, no Metal and no game data are needed.
// The seam under test is exactly the one the app uses: `wireWorldItems` builds
// the same object with the same two collaborators.

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct WorldItemRuntimeTests {
    private typealias Fixture = InventoryBaselineFixture

    static let cell = CellSceneLocation.exterior(CellCoordinate(x: 3, y: -4))
    static let looseItem = FormID(0x0000_0700)
    static let chestReference = FormID(0x0000_0710)

    /// A store, an item runtime and the reference index behind it. The index is
    /// returned because `WorldItemRuntime.references` is weak: dropping it
    /// would make every lookup answer nil halfway through a test.
    struct Harness {
        let store: WorldStateStore
        let runtime: WorldItemRuntime
        let references: PapyrusWorldFixtureReferences
    }

    /// One placed reference with no plugin record behind it. The spawn
    /// initializer is reused as a synthetic REFR constructor: it produces
    /// exactly a base, a placement and a stack count, which is all a take
    /// needs, and it keeps the fixture free of hand-assembled record bytes.
    private static func placedReference(
        formID: FormID,
        base: FormID,
        count: Int32 = 1,
        position: SIMD3<Float> = .zero
    ) -> PlacedReference {
        PlacedReference(
            spawn: ReferenceSpawnState(
                base: base,
                location: cell,
                placement: PlacedReference.Placement(position: position, rotation: .zero),
                count: count
            ),
            formID: formID
        )
    }

    private static func entry(
        formID: FormID,
        base: FormID,
        count: Int32 = 1
    ) -> RuntimeReferenceEntry {
        RuntimeReferenceEntry(
            key: .plugin(name: "skyrim.esm", objectID: formID.objectID),
            formID: formID,
            isPersistent: false,
            record: .reference(placedReference(formID: formID, base: base, count: count))
        )
    }

    static func interaction(
        reference: FormID,
        base: FormID,
        action: InteractionAction
    ) -> PlacedInteraction {
        PlacedInteraction(
            reference: reference,
            base: base,
            position: .zero,
            name: "Fixture",
            action: action,
            actionLabel: action.defaultLabel,
            sounds: nil
        )
    }

    static func harness(entries: [RuntimeReferenceEntry]) throws -> Harness {
        let store = WorldStateStore()
        let references = PapyrusWorldFixtureReferences(entries: entries, cell: cell)
        return try Harness(
            store: store,
            runtime: WorldItemRuntime(
                inventory: InventoryRuntime(store: store, baselines: Fixture.resolver()),
                references: references
            ),
            references: references
        )
    }

    /// The default fixture: one loose stack of three lockpicks and one chest.
    static func standardHarness() throws -> Harness {
        try harness(entries: [
            entry(formID: looseItem, base: Fixture.lockpick, count: 3),
            entry(formID: chestReference, base: Fixture.chest)
        ])
    }

    // MARK: - Take

    @Test func takeMovesTheWholeStackAndDeletesTheReference() throws {
        let harness = try Self.standardHarness()
        let target = Self.interaction(
            reference: Self.looseItem, base: Fixture.lockpick, action: .take
        )
        let outcome = try harness.runtime.take(target)

        #expect(outcome.count == 3)
        #expect(outcome.item == Fixture.lockpick)
        #expect(harness.runtime.inventory.count(of: Fixture.lockpick, in: .player) == 3)
        let key = ReferenceKey.plugin(name: "skyrim.esm", objectID: Self.looseItem.objectID)
        #expect(harness.store.component(ReferenceDeletionState.self, for: key)?.isDeleted == true)
        // The deletion is attributed to the cell the reference was resident in,
        // so exactly that cell rebuilds rather than every resident one.
        #expect(harness.store.dirtyCount(in: Self.cell) == 1)
    }

    /// A reference with no XCNT is one item, not zero and not nil.
    @Test func takeWithoutAnExplicitCountMovesOne() throws {
        let harness = try Self.harness(entries: [
            RuntimeReferenceEntry(
                key: .plugin(name: "skyrim.esm", objectID: Self.looseItem.objectID),
                formID: Self.looseItem,
                isPersistent: false,
                record: .reference(Self.placedReference(
                    formID: Self.looseItem, base: Fixture.sword
                ))
            )
        ])
        let outcome = try harness.runtime.take(
            Self.interaction(reference: Self.looseItem, base: Fixture.sword, action: .take)
        )
        #expect(outcome.count == 1)
    }

    @Test func takeRefusesAnInteractionThatIsNotAnItem() throws {
        let harness = try Self.standardHarness()
        #expect(throws: WorldItemError.notTakeable(Self.chestReference)) {
            try harness.runtime.take(
                Self.interaction(
                    reference: Self.chestReference, base: Fixture.chest, action: .search
                )
            )
        }
        #expect(harness.store.dirtyCount == 0)
    }

    /// A reference no resident cell knows about has no identity to record
    /// against, so the take fails and the player gains nothing.
    @Test func takeOfAnUnknownReferenceWritesNothing() throws {
        let harness = try Self.standardHarness()
        let ghost = FormID(0x0000_09FF)
        #expect(throws: WorldItemError.unknownReference(ghost)) {
            try harness.runtime.take(
                Self.interaction(reference: ghost, base: Fixture.lockpick, action: .take)
            )
        }
        #expect(harness.store.dirtyCount == 0)
        #expect(harness.runtime.inventory.inventory(of: .player).isEmpty)
    }

    // MARK: - Drop

    @Test func dropRemovesFromTheInventoryAndSpawnsAReference() throws {
        let harness = try Self.standardHarness()
        try harness.runtime.take(
            Self.interaction(reference: Self.looseItem, base: Fixture.lockpick, action: .take)
        )
        let key = try harness.runtime.drop(
            Fixture.lockpick,
            count: 2,
            at: DropPlacement(location: Self.cell, position: SIMD3(10, 20, 30))
        )

        #expect(harness.runtime.inventory.count(of: Fixture.lockpick, in: .player) == 1)
        let spawn = try #require(harness.store.component(ReferenceSpawnState.self, for: key))
        #expect(spawn.base == Fixture.lockpick)
        #expect(spawn.count == 2)
        #expect(spawn.location == Self.cell)
        #expect(spawn.placement.position == SIMD3(10, 20, 30))
        // Generated identity, addressable by a synthesized 0xFF-prefixed
        // FormID, which is what lets a cell build place it.
        #expect(key == .generated(1))
        #expect(SpawnedReferenceIdentity.formID(for: key) == FormID(0xFF00_0001))
    }

    /// Dropping more than the player carries is all-or-nothing: no state is
    /// written and no generated key is burned, so the allocator does not drift.
    @Test func dropOfMoreThanCarriedWritesNothingAndAllocatesNoKey() throws {
        let harness = try Self.standardHarness()
        #expect(throws: (any Error).self) {
            try harness.runtime.drop(
                Fixture.lockpick,
                count: 1,
                at: DropPlacement(location: Self.cell, position: .zero)
            )
        }
        #expect(harness.store.dirtyCount == 0)
        #expect(harness.store.nextGeneratedSequence == 1)
    }

    /// Taking a dropped item back resets its whole delta rather than marking it
    /// deleted, so the store — and every save after it — stops carrying an
    /// object that no longer exists.
    @Test func takingASpawnedReferenceLeavesNoStateBehind() throws {
        let harness = try Self.standardHarness()
        try harness.runtime.take(
            Self.interaction(reference: Self.looseItem, base: Fixture.lockpick, action: .take)
        )
        let key = try harness.runtime.drop(
            Fixture.lockpick,
            count: 3,
            at: DropPlacement(location: Self.cell, position: SIMD3(1, 2, 3))
        )
        let spawnedFormID = try #require(SpawnedReferenceIdentity.formID(for: key))
        harness.references.index = try RuntimeReferenceIndex(entries: [
            RuntimeReferenceEntry(
                key: key,
                formID: spawnedFormID,
                isPersistent: true,
                record: .reference(PlacedReference(
                    spawn: #require(harness.store.component(
                        ReferenceSpawnState.self, for: key
                    )),
                    formID: spawnedFormID
                ))
            )
        ])

        try harness.runtime.take(
            Self.interaction(
                reference: spawnedFormID, base: Fixture.lockpick, action: .take
            )
        )
        #expect(harness.runtime.inventory.count(of: Fixture.lockpick, in: .player) == 3)
        #expect(harness.store.delta(for: key) == nil)
        #expect(harness.store.isDirty(key) == false)
    }

    /// A dropped object lands in front of the player and below the eye, and a
    /// camera pointing straight up has nothing to lean on, so it lands
    /// directly below instead of over the player's head.
    @Test func dropPlacementLeadsTheCameraAndFallsToTheGround() {
        let ahead = WorldItemRuntime.dropPlacement(
            in: Self.cell, eye: SIMD3(100, 200, 300), forward: SIMD3(1, 0, 0)
        )
        #expect(ahead.position == SIMD3(
            100 + WorldItemRuntime.dropForwardOffset,
            200,
            300 - WorldItemRuntime.dropHeight
        ))
        let overhead = WorldItemRuntime.dropPlacement(
            in: Self.cell, eye: SIMD3(100, 200, 300), forward: SIMD3(0, 0, 1)
        )
        #expect(overhead.position == SIMD3(100, 200, 300 - WorldItemRuntime.dropHeight))
    }
}
