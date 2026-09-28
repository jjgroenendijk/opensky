// Runtime world-state streaming tests (issue #160, roadmap item 10.1.3):
// snapshot capture at dispatch, rebuild scheduling for resident cells, the
// stale-build race, rebuild cancellation on unload, and the conservative
// fan-out for an unattributed mutation.
//
// Everything runs through a real `WorldStateStore` wired to the streamer the
// same way `GameViewController.wireStreaming` wires it, and through
// `ManualCellBuildRunner` so the test controls exactly when each build
// completes. No Metal, no game data.

@testable import opensky
import simd
import Testing

@MainActor
struct CellStreamerRuntimeStateTests {
    // MARK: - Fixtures

    private static func coordinate(_ x: Int32, _ y: Int32) -> CellCoordinate {
        CellStreamerTests.coordinate(x, y)
    }

    private static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: "skyrim.esm", objectID: objectID)
    }

    private static func position(of coordinate: CellCoordinate) -> SIMD3<Float> {
        CellGridManager.cellCenter(of: coordinate)
    }

    /// A store, a manual runner and a streamer wired together exactly as
    /// `wireStreaming` wires them in the app.
    private struct Harness {
        let store: WorldStateStore
        let runner: ManualCellBuildRunner
        let streamer: CellStreamer
        /// Builds completed by `settle`, as an index into `runner.enqueued`.
        var completedCount = 0
    }

    private static func makeHarness(radius: Int32 = 0) -> Harness {
        let store = WorldStateStore()
        let runner = ManualCellBuildRunner()
        let streamer = CellStreamerTests.makeStreamer(runner: runner, radius: radius)
        streamer.stateSource = { store.snapshot() }
        store.onMutation = { [weak streamer] location, sequence in
            streamer?.noteStateMutation(in: location, sequence: sequence)
        }
        return Harness(store: store, runner: runner, streamer: streamer)
    }

    /// Runs frames until no new build is dispatched, completing each dispatched
    /// build with a scene stamped with the snapshot sequence it was handed.
    /// That stamping is what the production builder does, so the streamer's
    /// staleness comparison is exercised for real.
    private static func settle(
        _ harness: inout Harness,
        at cameraPosition: SIMD3<Float>,
        frames: Int = 64
    ) {
        for _ in 0 ..< frames {
            completeDispatchedBuilds(&harness)
            harness.streamer.update(cameraPosition: cameraPosition)
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

    private static func disable(_ objectID: UInt32, in harness: Harness, at cell: CellCoordinate) {
        harness.store.set(
            ReferenceEnableState.disabled,
            for: key(objectID),
            in: .exterior(cell)
        )
    }

    // MARK: - Snapshot capture at dispatch

    @Test
    func dispatchPassesTheSnapshotFromTheStateSource() throws {
        let harness = Self.makeHarness()
        Self.disable(0x10, in: harness, at: Self.coordinate(0, 0))

        harness.streamer.update(cameraPosition: Self.position(of: Self.coordinate(0, 0)))

        #expect(harness.runner.enqueued == [Self.coordinate(0, 0)])
        let state = try #require(harness.runner.enqueuedStates.first)
        #expect(state.sequence == 2)
        #expect(state[Self.key(0x10)]?.component(ReferenceEnableState.self) == .disabled)
    }

    @Test
    func dispatchWithNoStateSourceStillCarriesThePluginBaseline() {
        let runner = ManualCellBuildRunner()
        let streamer = CellStreamerTests.makeStreamer(runner: runner, radius: 0)

        streamer.update(cameraPosition: Self.position(of: Self.coordinate(0, 0)))

        #expect(runner.enqueuedStates == [.empty])
    }

    @Test
    func doorTransitionDispatchCarriesTheCurrentSnapshot() throws {
        var harness = Self.makeHarness()
        let cell = Self.coordinate(0, 0)
        Self.settle(&harness, at: Self.position(of: cell))
        Self.disable(0x20, in: harness, at: cell)

        harness.streamer.requestDoorTransition(
            CellStreamerTests.door(reference: 0x900, destination: 0x901, position: .zero)
        )

        let state = try #require(harness.runner.enqueuedDoorTransitionStates.first)
        #expect(state[Self.key(0x20)]?.component(ReferenceEnableState.self) == .disabled)
    }

    // MARK: - Rebuild of a resident cell

    @Test
    func mutatingAResidentCellRebuildsItThroughTheNormalBuildPath() throws {
        var harness = Self.makeHarness()
        let cell = Self.coordinate(0, 0)
        let camera = Self.position(of: cell)
        harness.streamer.update(cameraPosition: camera)
        harness.runner.complete(cell, with: .success(
            CellStreamerTests.cellScene(meshKeys: ["before"])
        ))
        harness.completedCount = 1
        harness.streamer.update(cameraPosition: camera)
        #expect(harness.streamer.residentCellCount == 1)

        Self.disable(0x30, in: harness, at: cell)
        #expect(harness.streamer.queuedRebuildCount == 1)

        // The rebuild reaches the runner with the delta, and the cell keeps
        // rendering its old scene while that build is in flight.
        harness.streamer.update(cameraPosition: camera)
        #expect(harness.runner.enqueued == [cell, cell])
        let state = try #require(harness.runner.enqueuedStates.last)
        #expect(state[Self.key(0x30)]?.component(ReferenceEnableState.self) == .disabled)
        #expect(harness.streamer.rebuildingCellCount == 1)
        #expect(harness.streamer.residentCellCount == 1)
        #expect(harness.streamer.composedCellCount == 1)

        // The replacement displaces the old scene on the next integration.
        harness.runner.complete(cell, with: .success(
            CellStreamerTests.cellScene(meshKeys: ["after"], stateSequence: state.sequence)
        ))
        harness.completedCount = 2
        harness.streamer.update(cameraPosition: camera)
        #expect(harness.streamer.residentCellCount == 1)
        #expect(harness.streamer.rebuildingCellCount == 0)
        #expect(harness.streamer.queuedRebuildCount == 0)

        // And nothing further is dispatched once the state is caught up.
        harness.streamer.update(cameraPosition: camera)
        #expect(harness.runner.enqueued.count == 2)
    }

    @Test
    func aRebuildIsDispatchedOnlyAfterFirstLoadsDrain() {
        var harness = Self.makeHarness(radius: 1)
        let camera = Self.position(of: Self.coordinate(0, 0))
        // Resolve just the center cell; the other eight stay in flight.
        harness.streamer.update(cameraPosition: camera)
        harness.runner.complete(Self.coordinate(0, 0), with: .success(
            CellStreamerTests.cellScene()
        ))
        harness.completedCount = 1
        harness.streamer.update(cameraPosition: camera)

        Self.disable(0x40, in: harness, at: Self.coordinate(0, 0))
        harness.streamer.update(cameraPosition: camera)

        // The next dispatch is a first load, not the rebuild.
        #expect(harness.runner.enqueued.last != Self.coordinate(0, 0))
        #expect(harness.streamer.queuedRebuildCount == 1)

        Self.settle(&harness, at: camera)
        #expect(harness.streamer.queuedRebuildCount == 0)
        #expect(harness.runner.enqueued.filter { $0 == Self.coordinate(0, 0) }.count == 2)
    }

    // MARK: - The in-flight race

    @Test
    func aMutationDuringAnInFlightBuildProducesExactlyOneRebuild() throws {
        var harness = Self.makeHarness()
        let cell = Self.coordinate(0, 0)
        let camera = Self.position(of: cell)

        // Build dispatched against the clean store (journal sequence 1)...
        harness.streamer.update(cameraPosition: camera)
        #expect(harness.runner.enqueuedStates.first?.sequence == 1)
        // ...then the mutation lands while it is still running.
        Self.disable(0x50, in: harness, at: cell)
        // The runner would dedupe a second enqueue for this coordinate, so the
        // streamer must hold the rebuild until the stale completion drains.
        #expect(harness.runner.enqueued.count == 1)

        harness.runner.complete(cell, with: .success(
            CellStreamerTests.cellScene(meshKeys: ["stale"], stateSequence: 1)
        ))
        harness.completedCount = 1
        harness.streamer.update(cameraPosition: camera)
        // The stale scene is integrated rather than dropped, so the cell is
        // drawable immediately, and the rebuild goes out in the same frame's
        // dispatch slot now that the runner's dedupe entry has cleared.
        #expect(harness.streamer.residentCellCount == 1)
        #expect(harness.streamer.rebuildingCellCount == 1)
        #expect(harness.runner.enqueued.count == 2)

        Self.settle(&harness, at: camera)

        // Exactly one rebuild, carrying the mutation, and nothing after it.
        #expect(harness.runner.enqueued == [cell, cell])
        let rebuildState = try #require(harness.runner.enqueuedStates.last)
        #expect(rebuildState.sequence >= 2)
        #expect(rebuildState[Self.key(0x50)]?.component(ReferenceEnableState.self) == .disabled)
        #expect(harness.streamer.queuedRebuildCount == 0)
        #expect(harness.streamer.rebuildingCellCount == 0)
    }

    @Test
    func aMutationDuringARebuildIsNeitherLostNorAppliedTwice() {
        var harness = Self.makeHarness()
        let cell = Self.coordinate(0, 0)
        let camera = Self.position(of: cell)
        Self.settle(&harness, at: camera)
        let loadCount = harness.runner.enqueued.count

        Self.disable(0x60, in: harness, at: cell)
        harness.streamer.update(cameraPosition: camera)
        #expect(harness.streamer.rebuildingCellCount == 1)

        // Second mutation while the first rebuild is in flight.
        Self.disable(0x61, in: harness, at: cell)
        Self.settle(&harness, at: camera)

        // Two rebuilds total -- one per mutation -- and the final resident
        // scene was built from state that includes both.
        #expect(harness.runner.enqueued.count == loadCount + 2)
        #expect(harness.streamer.queuedRebuildCount == 0)
        let finalState = harness.runner.enqueuedStates[harness.runner.enqueued.count - 1]
        #expect(finalState.sequence == harness.store.nextJournalSequence)
        #expect(finalState.dirtyCount == 2)
    }

    // MARK: - Eviction and reload

    @Test
    func stateSurvivesEvictionAndReappliesWhenTheCellReturns() throws {
        var harness = Self.makeHarness()
        let cell = Self.coordinate(0, 0)
        let home = Self.position(of: cell)
        Self.settle(&harness, at: home)

        Self.disable(0x70, in: harness, at: cell)
        Self.settle(&harness, at: home)

        // Leave, so the cell is unloaded and its scene dropped entirely.
        let far = Self.position(of: Self.coordinate(9, 0))
        Self.settle(&harness, at: far)
        #expect(!harness.streamer.residentCoordinates.contains(cell))

        // Come back: the reload carries the delta, because it comes from the
        // store rather than from anything the unloaded scene held.
        let beforeReturn = harness.runner.enqueued.count
        Self.settle(&harness, at: home)
        let reloadIndex = try #require(
            (beforeReturn ..< harness.runner.enqueued.count)
                .first { harness.runner.enqueued[$0] == cell }
        )
        let state = harness.runner.enqueuedStates[reloadIndex]
        #expect(state[Self.key(0x70)]?.component(ReferenceEnableState.self) == .disabled)
        #expect(harness.streamer.residentCoordinates.contains(cell))
    }

    @Test
    func unloadingACellCancelsItsPendingRebuild() {
        var harness = Self.makeHarness()
        let cell = Self.coordinate(0, 0)
        let home = Self.position(of: cell)
        Self.settle(&harness, at: home)

        Self.disable(0x80, in: harness, at: cell)
        #expect(harness.streamer.queuedRebuildCount == 1)

        // Leave before the rebuild is dispatched.
        let far = Self.position(of: Self.coordinate(9, 0))
        harness.streamer.update(cameraPosition: far)
        #expect(harness.streamer.queuedRebuildCount == 0)

        let afterLeaving = harness.runner.enqueued.count
        Self.settle(&harness, at: far)
        // No ghost rebuild for the removed cell.
        #expect(!harness.runner.enqueued[afterLeaving...].contains(cell))
        #expect(harness.streamer.rebuildingCellCount == 0)
    }

    // MARK: - Unattributed mutations

    @Test
    func anUnattributedMutationRebuildsEveryResidentCell() {
        var harness = Self.makeHarness(radius: 1)
        let camera = Self.position(of: Self.coordinate(0, 0))
        Self.settle(&harness, at: camera)
        #expect(harness.streamer.residentCellCount == 9)
        let loadCount = harness.runner.enqueued.count

        harness.store.set(ReferenceEnableState.disabled, for: Self.key(0x90))
        #expect(harness.streamer.queuedRebuildCount == 9)

        Self.settle(&harness, at: camera)
        #expect(harness.runner.enqueued.count == loadCount + 9)
        #expect(harness.streamer.residentCellCount == 9)
        #expect(harness.streamer.queuedRebuildCount == 0)
    }

    @Test
    func aMutationInAnUnaccountedCellSchedulesNothing() {
        var harness = Self.makeHarness()
        let camera = Self.position(of: Self.coordinate(0, 0))
        Self.settle(&harness, at: camera)
        let loadCount = harness.runner.enqueued.count

        Self.disable(0xA0, in: harness, at: Self.coordinate(40, 40))

        #expect(harness.streamer.queuedRebuildCount == 0)
        Self.settle(&harness, at: camera)
        #expect(harness.runner.enqueued.count == loadCount)
    }
}
