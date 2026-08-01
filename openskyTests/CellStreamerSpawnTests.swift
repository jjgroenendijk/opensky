// Streaming behaviour of dropped objects (issue #177, roadmap item 12.1.3):
// a drop rebuilds the cell it landed in, survives that cell being evicted and
// reloaded, resolves the in-flight-build race deterministically, and comes back
// from a save/load cycle with its identity intact.
//
// The harness is the M10 one: a real `WorldStateStore` wired to the streamer
// exactly as `GameViewController.wireStreaming` wires it, and a
// `ManualCellBuildRunner` so the test decides when each build finishes. No
// Metal, no game data.

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct CellStreamerSpawnTests {
    private typealias Fixture = InventoryBaselineFixture

    private static let home = CellCoordinate(x: 0, y: 0)
    private static let faraway = CellCoordinate(x: 40, y: 40)

    private struct Harness {
        let store: WorldStateStore
        let runner: ManualCellBuildRunner
        let streamer: CellStreamer
        let items: WorldItemRuntime
        var completedCount = 0
    }

    private static func makeHarness() throws -> Harness {
        let store = WorldStateStore()
        let runner = ManualCellBuildRunner()
        let streamer = CellStreamerTests.makeStreamer(runner: runner, radius: 0)
        streamer.stateSource = { store.snapshot() }
        store.onMutation = { [weak streamer] location, sequence in
            streamer?.noteStateMutation(in: location, sequence: sequence)
        }
        let items = try WorldItemRuntime(
            inventory: InventoryRuntime(store: store, baselines: Fixture.resolver()),
            references: streamer
        )
        // Something to drop. The player's baseline is empty by definition, so
        // the test stocks it through the same accounting API a take uses.
        try items.inventory.add(Fixture.lockpick, count: 5, to: .player)
        return Harness(store: store, runner: runner, streamer: streamer, items: items)
    }

    private static func settle(
        _ harness: inout Harness,
        at coordinate: CellCoordinate,
        frames: Int = 16
    ) {
        let position = CellGridManager.cellCenter(of: coordinate)
        for _ in 0 ..< frames {
            completeDispatchedBuilds(&harness)
            harness.streamer.update(cameraPosition: position)
        }
        completeDispatchedBuilds(&harness)
    }

    private static func completeDispatchedBuilds(_ harness: inout Harness) {
        while harness.completedCount < harness.runner.enqueued.count {
            let index = harness.completedCount
            harness.runner.complete(
                harness.runner.enqueued[index],
                with: .success(CellStreamerTests.cellScene(
                    stateSequence: harness.runner.enqueuedStates[index].sequence
                ))
            )
            harness.completedCount += 1
        }
    }

    @discardableResult
    private static func drop(
        _ harness: Harness,
        count: Int32 = 1,
        in cell: CellCoordinate = home
    ) throws -> ReferenceKey {
        try harness.items.drop(
            Fixture.lockpick,
            count: count,
            at: DropPlacement(location: .exterior(cell), position: SIMD3(1, 2, 3))
        )
    }

    /// Every spawn the state a build was handed would place in `cell`.
    private static func spawns(
        _ state: WorldStateSnapshot,
        in cell: CellCoordinate
    ) -> [ReferenceSpawnState] {
        state.entries.compactMap { $0.delta.component(ReferenceSpawnState.self) }
            .filter { $0.location == .exterior(cell) }
    }

    // MARK: - Visibility

    /// The drop is one ordinary store write attributed to one cell, so the
    /// existing rebuild machinery makes it visible with no new path.
    @Test func aDropRebuildsTheCellItLandedIn() throws {
        var harness = try Self.makeHarness()
        Self.settle(&harness, at: Self.home)
        let buildsBeforeDrop = harness.runner.enqueued.count

        try Self.drop(harness)
        #expect(harness.streamer.queuedRebuildCount == 1)

        Self.settle(&harness, at: Self.home)
        #expect(harness.runner.enqueued.count > buildsBeforeDrop)
        let rebuiltState = try #require(harness.runner.enqueuedStates.last)
        #expect(Self.spawns(rebuiltState, in: Self.home).count == 1)
    }

    /// Eviction is not a state change: state lives in the store, which outlives
    /// every cell, so the returning cell rebuilds with the dropped item still
    /// in it.
    @Test func aDroppedObjectSurvivesEvictionAndReload() throws {
        var harness = try Self.makeHarness()
        Self.settle(&harness, at: Self.home)
        try Self.drop(harness, count: 3)
        Self.settle(&harness, at: Self.home)

        Self.settle(&harness, at: Self.faraway)
        #expect(harness.streamer.residentCellCount >= 1)
        // Nothing was written while the cell was away.
        #expect(harness.store.dirtyCount == 2)

        Self.settle(&harness, at: Self.home)
        let returned = try #require(harness.runner.enqueuedStates.last)
        let spawn = try #require(Self.spawns(returned, in: Self.home).first)
        #expect(spawn.count == 3)
        #expect(spawn.base == Fixture.lockpick)
    }

    /// The in-flight race, resolved by the same `stateSequence` comparison M10
    /// introduced: the build that was already running is integrated, then a
    /// rebuild is queued because it predates the drop.
    @Test func aDropDuringAnInFlightBuildRebuildsAgainstTheNewerState() throws {
        var harness = try Self.makeHarness()
        // One frame dispatches the first build; the drop lands before it
        // completes, so its snapshot cannot contain the spawn.
        harness.streamer.update(cameraPosition: CellGridManager.cellCenter(of: Self.home))
        #expect(harness.runner.enqueued.count == 1)
        #expect(Self.spawns(harness.runner.enqueuedStates[0], in: Self.home).isEmpty)

        try Self.drop(harness)
        Self.settle(&harness, at: Self.home)

        let states = harness.runner.enqueuedStates
        #expect(states.count >= 2)
        #expect(try Self.spawns(#require(states.last), in: Self.home).count == 1)
        #expect(harness.streamer.queuedRebuildCount == 0)
    }

    // MARK: - Save round trip

    /// A drop, a save, a load, and the object is still there under the same
    /// generated key — with the allocator resumed so the next drop cannot
    /// collide with it.
    @Test func takeAndDropSurviveASaveAndLoadCycle() throws {
        var harness = try Self.makeHarness()
        Self.settle(&harness, at: Self.home)
        let key = try Self.drop(harness, count: 2)

        let data = OpenSkySaveEncoder.encode(
            snapshot: harness.store.snapshot(),
            fingerprint: [],
            metadata: SaveCreationMetadata(creationTimestamp: 0, appVersion: "test")
        )
        let restored = WorldStateStore()
        try restored.restore(from: OpenSkySaveDecoder.decode(data).snapshot)

        let spawn = try #require(restored.component(ReferenceSpawnState.self, for: key))
        #expect(spawn.count == 2)
        #expect(spawn.location == .exterior(Self.home))
        #expect(restored.nextGeneratedSequence == harness.store.nextGeneratedSequence)
        // The restored player still carries what the drop left behind, so the
        // items are conserved across the whole cycle.
        let baselines = try Fixture.resolver()
        let inventory = InventoryRuntime(store: restored, baselines: baselines)
        #expect(inventory.count(of: Fixture.lockpick, in: .player) == 3)
        #expect(restored.allocateGeneratedKey() != key)
    }
}
