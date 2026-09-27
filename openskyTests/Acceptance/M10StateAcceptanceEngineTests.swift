// Satellite of M10StateAcceptanceTests (issue #162): the engine half of the
// M10.1 gate, with no fakes on the engine side at all.
//
// Split from the parent file because the two halves stand alone — the parent
// drives the sidebar panel through `FakeWorldProviders`, while everything here
// runs a real `WorldStateStore` wired to a real `CellStreamer` exactly as
// `GameViewController.wireStreaming` wires them, and a real `OpenSkySaveStore`
// writing to a temporary directory. The only test double is
// `ManualCellBuildRunner`, which stands in for the serial build queue so the
// test controls when each build completes; it records the world-state snapshot
// each build ran against, which is how "the delta is reapplied on reload"
// becomes an assertion rather than a claim.
//
// No Metal and no game data in the streaming cases; the last case builds a real
// cell scene from synthetic ESM and NIF bytes and is gated on a Metal device.

import Foundation
@testable import opensky
import simd
import Testing

/// A store, a manual runner and a streamer wired together the way the app wires
/// them, mirroring `CellStreamerRuntimeStateTests.Harness`.
@MainActor
private struct M10EngineHarness {
    let store = WorldStateStore()
    let runner = ManualCellBuildRunner()
    let streamer: CellStreamer
    /// Builds completed by `settle`, as an index into `runner.enqueued`.
    var completedCount = 0

    init(radius: Int32 = 0) {
        streamer = CellStreamerTests.makeStreamer(runner: runner, radius: radius)
        let liveStore = store
        streamer.stateSource = { liveStore.snapshot() }
        store.onMutation = { [weak streamer] location, sequence in
            streamer?.noteStateMutation(in: location, sequence: sequence)
        }
    }

    /// Runs frames until no new build is dispatched, completing each dispatched
    /// build with a scene stamped with the snapshot sequence it was handed, the
    /// way the production builder stamps it.
    static func settle(
        _ harness: inout M10EngineHarness,
        at cameraPosition: SIMD3<Float>,
        frames: Int = 64
    ) {
        for _ in 0 ..< frames {
            completeDispatchedBuilds(&harness)
            harness.streamer.update(cameraPosition: cameraPosition)
        }
        completeDispatchedBuilds(&harness)
    }

    private static func completeDispatchedBuilds(_ harness: inout M10EngineHarness) {
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
}

extension M10StateAcceptanceTests {
    // MARK: Step 5 — the engine round trip

    /// The core proof of the gate. Two references are mutated in a resident
    /// cell; the streamer picks the mutation up; the cell is unloaded by walking
    /// away and reloaded by walking back, and the reload's build carries the
    /// deltas; the state is then written to a real save slot, read back, and
    /// restored into a brand-new store that is in the identical end state,
    /// generated-key allocator included.
    @Test @MainActor
    func runtimeChangesSurviveEvictionReloadAndTheSaveRoundTrip() throws {
        var harness = M10EngineHarness()
        let cell = CellCoordinate(x: 0, y: 0)
        let home = CellGridManager.cellCenter(of: cell)
        M10EngineHarness.settle(&harness, at: home)
        #expect(harness.streamer.residentCoordinates.contains(cell))

        Self.mutate(harness.store, in: .exterior(cell))
        #expect(harness.store.dirtyCount == 2)
        #expect(harness.store.dirtyCount(in: .exterior(cell)) == 2)

        // The streamer noticed, and the rebuild it dispatches runs against
        // state that contains both deltas.
        #expect(harness.streamer.queuedRebuildCount == 1)
        M10EngineHarness.settle(&harness, at: home)
        try Self.expectBothDeltas(in: #require(harness.runner.enqueuedStates.last))

        // Cross a streaming boundary: the cell unloads and its scene is dropped
        // entirely, so anything reapplied afterwards can only come from the
        // store.
        let far = CellGridManager.cellCenter(of: CellCoordinate(x: 9, y: 0))
        M10EngineHarness.settle(&harness, at: far)
        #expect(!harness.streamer.residentCoordinates.contains(cell))

        let beforeReturn = harness.runner.enqueued.count
        M10EngineHarness.settle(&harness, at: home)
        let reloadIndex = try #require(
            (beforeReturn ..< harness.runner.enqueued.count)
                .first { harness.runner.enqueued[$0] == cell },
            "the cell never reloaded"
        )
        try Self.expectBothDeltas(in: harness.runner.enqueuedStates[reloadIndex])
        #expect(harness.streamer.residentCoordinates.contains(cell))

        // Two generated keys are minted so the allocator has a position worth
        // resuming rather than its initial one.
        #expect(harness.store.allocateGeneratedKey() == .generated(1))
        #expect(harness.store.allocateGeneratedKey() == .generated(2))

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let saves = OpenSkySaveStore(directory: directory)
        try saves.save(
            snapshot: harness.store.snapshot(),
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata,
            toSlot: Self.slot
        )
        let file = try saves.load(
            slot: Self.slot, verifyingAgainst: OpenSkySaveFixture.fingerprint
        )

        // A brand-new store restored from the file is in the identical end
        // state. Snapshot equality covers the entries and the allocator
        // position and deliberately ignores the journal sequence, so this is a
        // genuine "same world" assertion and not a same-session one.
        let fresh = WorldStateStore()
        fresh.restore(from: file.snapshot)
        #expect(fresh.snapshot() == harness.store.snapshot())
        #expect(fresh.dirtyCount == 2)
        #expect(fresh.dirtyCount(in: .exterior(cell)) == 2)
        try Self.expectBothDeltas(in: fresh.snapshot())
        // The allocator resumed where the saved session left off, so a restored
        // session cannot mint a key that collides with a saved one.
        #expect(fresh.allocateGeneratedKey() == .generated(3))
        // Restoring replays rather than re-records: no journal entries and no
        // sequence movement.
        #expect(fresh.journalEntries.isEmpty)
    }

    /// Loading a save into a live session rebuilds the resident cells against
    /// the restored state, which is what makes a load visible in the world
    /// rather than only in the store.
    @Test @MainActor
    func loadingASaveRebuildsTheResidentCellsFromTheRestoredState() throws {
        let cell = CellCoordinate(x: 0, y: 0)
        let saved = WorldStateStore()
        Self.mutate(saved, in: .exterior(cell))

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let saves = OpenSkySaveStore(directory: directory)
        try saves.save(
            snapshot: saved.snapshot(),
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata,
            toSlot: Self.slot
        )

        // A different session, with a clean store and a resident cell.
        var harness = M10EngineHarness(radius: 1)
        let home = CellGridManager.cellCenter(of: cell)
        M10EngineHarness.settle(&harness, at: home)
        #expect(harness.streamer.residentCellCount == 9)
        #expect(harness.store.dirtyCount == 0)
        let beforeLoad = harness.runner.enqueued.count

        let reloaded = try saves.load(slot: Self.slot)
        harness.store.restore(from: reloaded.snapshot)
        #expect(harness.store.dirtyCount == 2)
        // The restore is announced as one unattributed mutation, so every
        // resident cell is queued for a rebuild.
        #expect(harness.streamer.queuedRebuildCount == 9)

        M10EngineHarness.settle(&harness, at: home)
        #expect(harness.runner.enqueued.count == beforeLoad + 9)
        #expect(harness.streamer.queuedRebuildCount == 0)
        try Self.expectBothDeltas(in: #require(harness.runner.enqueuedStates.last))
    }

    /// A save written against one load order is refused against another, with
    /// the difference named in the error rather than silently applied.
    @Test
    func aSaveFromADifferentLoadOrderIsRefused() throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let saves = OpenSkySaveStore(directory: directory)
        try saves.save(
            snapshot: OpenSkySaveFixture.richSnapshot(),
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata,
            toSlot: Self.slot
        )

        let doctored = OpenSkySaveFixture.fingerprint.dropLast()
        #expect(throws: OpenSkySaveError.self) {
            try saves.load(slot: Self.slot, verifyingAgainst: Array(doctored))
        }
        // The same file still loads against the load order it was written for.
        let file = try saves.load(
            slot: Self.slot, verifyingAgainst: OpenSkySaveFixture.fingerprint
        )
        #expect(file.snapshot == OpenSkySaveFixture.richSnapshot())
    }

    // MARK: Step 6 — the restored state reaches a real cell build

    /// End of the chain: a cell built from the restored snapshot drops the
    /// disabled reference and moves the nudged one exactly as a cell built from
    /// the original snapshot does. Real ESM and NIF bytes, both synthetic, and a
    /// real `CellSceneBuilder`, so this is the step where the round trip becomes
    /// something a user would see on screen.
    @Test(.enabled(if: CellSceneBuilderTests.hasDevice)) @MainActor
    func restoredStateReappliesInARealCellBuild() throws {
        let builder = try CellSceneBuilderTests()
        try builder.writeLooseFile("meshes/arch/solid.nif", builder.collisionRenderNIF())
        let pluginData = builder.plugin(
            temporaryRefs: builder.refrRecord(
                formID: Self.disabledObjectID, base: 0x100, position: SIMD3(10, 20, 30)
            ) + builder.refrRecord(
                formID: Self.movedObjectID, base: 0x100, position: SIMD3(-10, 0, 0)
            ),
            statRecords: builder.statRecord(formID: 0x100, modelPath: "arch\\solid.nif")
        )
        let authored = try builder.build(pluginData: pluginData)
        #expect(builder.instanceTranslations(authored).count == 2)

        let store = WorldStateStore()
        Self.mutate(store, in: .exterior(CellCoordinate(x: 6, y: -2)))
        let mutated = try builder.build(pluginData: pluginData, state: store.snapshot())
        #expect(builder.instanceTranslations(mutated) == [Self.movedPosition])
        #expect(mutated.summary.runtimeDisabledSkipCount == 1)
        #expect(mutated.staticCollision.shapes.count == 1)

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let saves = OpenSkySaveStore(directory: directory)
        try saves.save(
            snapshot: store.snapshot(),
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata,
            toSlot: Self.slot
        )
        let fresh = WorldStateStore()
        let reloaded = try saves.load(slot: Self.slot)
        fresh.restore(from: reloaded.snapshot)

        let restored = try builder.build(pluginData: pluginData, state: fresh.snapshot())
        #expect(builder.instanceTranslations(restored) == builder.instanceTranslations(mutated))
        #expect(restored.summary.runtimeDisabledSkipCount == 1)
        #expect(restored.summary.drawnRefCount == mutated.summary.drawnRefCount)
        #expect(restored.staticCollision.shapes.count == 1)
        // The reference the player disabled is still addressable, so it can be
        // enabled again in the restored session.
        #expect(restored.references.entry(for: FormID(Self.disabledObjectID)) != nil)
    }

    // MARK: Shared state

    /// Slot every case here writes to. Named after the gate rather than after
    /// the default slot so a stray file is obviously a test artifact.
    private static let slot = "m10-acceptance"

    private static let disabledObjectID: UInt32 = 0x200
    private static let movedObjectID: UInt32 = 0x201
    private static let movedPosition = SIMD3<Float>(500, 600, 700)

    private static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: "skyrim.esm", objectID: objectID)
    }

    /// The two mutations the gate names: one reference disabled, one moved.
    /// Applied through `WorldStateStore.set` exactly as the panel's Disable and
    /// Nudge buttons apply them.
    @MainActor
    private static func mutate(_ store: WorldStateStore, in cell: CellSceneLocation) {
        #expect(store.set(ReferenceEnableState.disabled, for: key(disabledObjectID), in: cell))
        #expect(store.set(
            ReferenceTransformOverride(position: movedPosition),
            for: key(movedObjectID),
            in: cell
        ))
    }

    private static func expectBothDeltas(in state: WorldStateSnapshot) throws {
        #expect(state.dirtyCount >= 2)
        #expect(
            state[key(disabledObjectID)]?.component(ReferenceEnableState.self) == .disabled
        )
        let transform = try #require(
            state[key(movedObjectID)]?.component(ReferenceTransformOverride.self)
        )
        #expect(transform.position == movedPosition)
    }
}
