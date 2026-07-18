// CellStreamer wiring (todo 3.2 async build): request dedupe, void/failed
// no-retry, one-recompose-per-frame integration budget, unload on recenter,
// out-of-order completion tolerance, and first-cell-only camera reseed. Driven
// through a manual build runner + synthetic CellScenes -- no Metal, no game
// data (AGENTS.md testing rule).

import Foundation
@testable import opensky
import simd
import Testing

/// Test build runner: the test stages completions and controls their order,
/// standing in for the serial DispatchQueue without any async timing.
nonisolated final class ManualCellBuildRunner: CellBuildRunning {
    private(set) var enqueued: [CellCoordinate] = []
    private(set) var evictedMeshKeys: [Set<String>] = []
    private(set) var evictedTextureKeys: [Set<String>] = []
    private(set) var enqueuedDoorTransitions: [FormID] = []
    private var ready: [CellBuildResult] = []
    private var readyDoorTransitions: [DoorTransitionBuildResult] = []

    func enqueue(_ coordinate: CellCoordinate) {
        enqueued.append(coordinate)
    }

    func complete(_ coordinate: CellCoordinate, with result: Result<CellScene, any Error>) {
        ready.append(CellBuildResult(coordinate: coordinate, result: result))
    }

    func drainCompleted() -> [CellBuildResult] {
        let out = ready
        ready.removeAll(keepingCapacity: true)
        return out
    }

    func enqueueEviction(
        droppingMeshKeys meshKeys: Set<String>,
        droppingTextureKeys textureKeys: Set<String>
    ) {
        evictedMeshKeys.append(meshKeys)
        evictedTextureKeys.append(textureKeys)
    }

    func enqueueDoorTransition(from sourceDoor: FormID) {
        enqueuedDoorTransitions.append(sourceDoor)
    }

    func completeDoorTransition(
        from sourceDoor: FormID,
        with result: Result<DoorTransition, any Error>
    ) {
        readyDoorTransitions.append(DoorTransitionBuildResult(
            sourceDoor: sourceDoor, result: result
        ))
    }

    func drainCompletedDoorTransitions() -> [DoorTransitionBuildResult] {
        let out = readyDoorTransitions
        readyDoorTransitions.removeAll(keepingCapacity: true)
        return out
    }
}

private enum FakeBuildError: Error { case broken }

@MainActor
struct CellStreamerTests {
    static func coordinate(_ x: Int32, _ y: Int32) -> CellCoordinate {
        CellCoordinate(x: x, y: y)
    }

    /// Synthetic built cell: empty draw list, optional bounds (so the first
    /// integrated cell can frame a camera) and asset keys (for eviction tests).
    static func cellScene(
        bounds: (min: SIMD3<Float>, max: SIMD3<Float>)? = (SIMD3(0, 0, 0), SIMD3(10, 10, 10)),
        meshKeys: Set<String> = [],
        textureKeys: Set<String> = [],
        location: CellSceneLocation? = nil,
        doors: [PlacedDoor] = []
    ) -> CellScene {
        CellScene(
            renderScene: RenderScene(instances: []),
            summary: CellLoadSummary(
                cellName: "test", gridX: 0, gridY: 0,
                totalRefCount: 0, drawnRefCount: 0,
                unsupportedBaseSkipCount: 0, markerSkipCount: 0,
                modelFailureSkipCount: 0, malformedRefSkipCount: 0,
                modelCount: 0, textureCount: 0, missingTextureCount: 0
            ),
            bounds: bounds,
            location: location,
            doors: doors,
            assets: CellAssets(meshKeys: meshKeys, textureKeys: textureKeys)
        )
    }

    static func door(
        reference: UInt32,
        destination: UInt32,
        position: SIMD3<Float>
    ) -> PlacedDoor {
        PlacedDoor(
            reference: FormID(reference),
            position: position,
            destination: PlacedReference.TeleportDestination(
                door: FormID(destination),
                placement: PlacedReference.Placement(position: position, rotation: .zero),
                flags: []
            )
        )
    }

    /// World center of cell (0,0); keeps the grid centered without recentering.
    static let center = CellGridManager.cellCenter(of: coordinate(0, 0))

    static func makeStreamer(
        runner: ManualCellBuildRunner,
        radius: Int32 = 1,
        sink: @escaping CellStreamer.SceneSink = { _, _ in }
    ) -> CellStreamer {
        CellStreamer(
            center: coordinate(0, 0), radius: radius, runner: runner, sink: sink
        )
    }

    // MARK: - Request dedupe

    @Test
    func firstUpdateSubmitsOneBuildAndQueuesRestWithoutDuplicates() {
        let runner = ManualCellBuildRunner()
        let streamer = Self.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Self.center)
        #expect(runner.enqueued == [Self.coordinate(0, 0)])
        #expect(streamer.queuedRequestCount == 8)
        #expect(streamer.inFlightCellCount == 9)

        // Nothing completed -> no second build reaches the runner.
        streamer.update(cameraPosition: Self.center)
        #expect(runner.enqueued.count == 1)
    }

    @Test
    func centerCellIsRequestedFirst() {
        let runner = ManualCellBuildRunner()
        let streamer = Self.makeStreamer(runner: runner, radius: 2)
        streamer.update(cameraPosition: Self.center)
        #expect(runner.enqueued.first == Self.coordinate(0, 0))
    }

    // MARK: - No-retry bookkeeping

    @Test
    func voidCellIsNeverReRequested() {
        let runner = ManualCellBuildRunner()
        let streamer = Self.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Self.center)

        runner.complete(Self.coordinate(0, 0), with: .failure(CellSceneError.cellNotFound(
            worldspaceEditorID: "Tamriel", gridX: 0, gridY: 0
        )))
        streamer.update(cameraPosition: Self.center)
        #expect(streamer.voidCellCount == 1)

        // Many frames later: the void slot stays accounted, no retry storm.
        for _ in 0 ..< 10 {
            streamer.update(cameraPosition: Self.center)
        }
        #expect(runner.enqueued.filter { $0 == Self.coordinate(0, 0) }.count == 1)
        #expect(streamer.voidCellCount == 1)
    }

    @Test
    func failedCellIsNeverReRequested() {
        let runner = ManualCellBuildRunner()
        let streamer = Self.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Self.center)

        runner.complete(Self.coordinate(0, 0), with: .failure(FakeBuildError.broken))
        for _ in 0 ..< 10 {
            streamer.update(cameraPosition: Self.center)
        }
        #expect(streamer.failedCellCount == 1)
        #expect(runner.enqueued.filter { $0 == Self.coordinate(0, 0) }.count == 1)
    }

    // MARK: - Integration budget

    @Test
    func integratesAtMostOneCellPerFrame() {
        let runner = ManualCellBuildRunner()
        let streamer = Self.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Self.center)

        // Three drawable cells finish at once.
        for cell in [Self.coordinate(0, 0), Self.coordinate(1, 0), Self.coordinate(-1, 0)] {
            runner.complete(cell, with: .success(Self.cellScene()))
        }
        streamer.update(cameraPosition: Self.center)
        #expect(streamer.residentCellCount == 1)
        streamer.update(cameraPosition: Self.center)
        #expect(streamer.residentCellCount == 2)
        streamer.update(cameraPosition: Self.center)
        #expect(streamer.residentCellCount == 3)
        #expect(streamer.pendingCompletionCount == 0)
    }

    @Test
    func voidAndFailedDoNotConsumeTheIntegrationBudget() {
        let runner = ManualCellBuildRunner()
        let streamer = Self.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Self.center)

        // A void, a failure, then a drawable cell -- cheap outcomes drain
        // freely, the drawable one still integrates the same frame.
        runner.complete(Self.coordinate(1, 1), with: .failure(CellSceneError.cellNotFound(
            worldspaceEditorID: "Tamriel", gridX: 1, gridY: 1
        )))
        runner.complete(Self.coordinate(-1, -1), with: .failure(FakeBuildError.broken))
        runner.complete(Self.coordinate(0, 0), with: .success(Self.cellScene()))
        streamer.update(cameraPosition: Self.center)
        #expect(streamer.residentCellCount == 1)
        #expect(streamer.voidCellCount == 1)
        #expect(streamer.failedCellCount == 1)
    }

    // MARK: - Out-of-order completions

    @Test
    func outOfOrderCompletionsAllIntegrate() {
        let runner = ManualCellBuildRunner()
        let streamer = Self.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Self.center)

        // In-grid cells (radius 1), delivered in a non-dispatch order.
        let cells = [Self.coordinate(1, 1), Self.coordinate(0, 0), Self.coordinate(-1, 1)]
        for cell in cells {
            runner.complete(cell, with: .success(Self.cellScene()))
        }
        // One per frame regardless of delivery order.
        for _ in cells {
            streamer.update(cameraPosition: Self.center)
        }
        #expect(streamer.residentCellCount == 3)
    }

    // MARK: - Unload on recenter

    @Test
    func recenterUnloadsCellsThatLeftTheGrid() {
        let runner = ManualCellBuildRunner()
        let streamer = Self.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Self.center)

        // Resolve the whole 3x3 as drawable.
        let grid = (-1 ... 1)
            .flatMap { x in (-1 ... 1).map { Self.coordinate(Int32(x), Int32($0)) } }
        for cell in grid {
            runner.complete(cell, with: .success(Self.cellScene()))
        }
        for _ in grid {
            streamer.update(cameraPosition: Self.center)
        }
        #expect(streamer.residentCellCount == 9)

        // Jump far away: every old cell leaves the grid -> all dropped.
        let far = CellGridManager.cellCenter(of: Self.coordinate(5, 0))
        streamer.update(cameraPosition: far)
        #expect(streamer.residentCellCount == 0)
        // And a fresh 3x3 gets requested around the new center.
        #expect(runner.enqueued.filter { $0 == Self.coordinate(5, 0) }.count == 1)
    }

    @Test
    func staleCompletionAfterUnloadIsDropped() {
        let runner = ManualCellBuildRunner()
        let streamer = Self.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Self.center)

        // Seed the real camera, then let the next submitted neighbor remain
        // active while that camera recenters far away.
        runner.complete(Self.coordinate(0, 0), with: .success(Self.cellScene()))
        streamer.update(cameraPosition: Self.center)

        let far = CellGridManager.cellCenter(of: Self.coordinate(5, 0))
        streamer.update(cameraPosition: far)

        // A build from the old grid lands late -> discarded, not resident.
        runner.complete(Self.coordinate(-1, 0), with: .success(Self.cellScene()))
        streamer.update(cameraPosition: far)
        #expect(streamer.residentCellCount == 0)
    }

    // MARK: - Eviction on unload

    /// Fills the 3x3 (each cell with its own mesh/texture keys), then jumps far
    /// away so the whole grid unloads -- every departed asset is scheduled for
    /// eviction (no resident cell remains to keep any of them).
    @Test
    func recenterEvictsEveryDepartedCellsAssets() {
        let runner = ManualCellBuildRunner()
        let streamer = Self.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Self.center)

        let grid = (-1 ... 1)
            .flatMap { x in (-1 ... 1).map { Self.coordinate(Int32(x), Int32($0)) } }
        for cell in grid {
            runner.complete(cell, with: .success(Self.cellScene(
                meshKeys: ["m\(cell.x)_\(cell.y)"], textureKeys: ["t\(cell.x)_\(cell.y)"]
            )))
        }
        for _ in grid {
            streamer.update(cameraPosition: Self.center)
        }
        #expect(streamer.residentCellCount == 9)

        // Far jump: disjoint new grid, so the whole old grid is dropped.
        streamer.update(cameraPosition: CellGridManager.cellCenter(of: Self.coordinate(9, 0)))
        let droppedMesh = runner.evictedMeshKeys.last
        #expect(droppedMesh == Set(grid.map { "m\($0.x)_\($0.y)" }))
        let droppedTexture = runner.evictedTextureKeys.last
        #expect(droppedTexture == Set(grid.map { "t\($0.x)_\($0.y)" }))
    }

    /// An asset a still-resident cell shares is never evicted when a neighbor
    /// unloads -- the drop-set subtracts the resident union.
    @Test
    func sharedAssetsSurviveWhenANeighborUnloads() {
        let runner = ManualCellBuildRunner()
        let streamer = Self.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Self.center)

        let grid = (-1 ... 1)
            .flatMap { x in (-1 ... 1).map { Self.coordinate(Int32(x), Int32($0)) } }
        for cell in grid {
            // Every cell shares "common"; each also has a unique key.
            runner.complete(cell, with: .success(Self.cellScene(
                meshKeys: ["m\(cell.x)_\(cell.y)", "common"]
            )))
        }
        for _ in grid {
            streamer.update(cameraPosition: Self.center)
        }

        // One cell east: unloads the x = -1 column only; x = 0/1 stay resident
        // and still use "common".
        streamer.update(cameraPosition: CellGridManager.cellCenter(of: Self.coordinate(1, 0)))
        let dropped = runner.evictedMeshKeys.last ?? []
        #expect(!dropped.contains("common"), "shared asset evicted while still in use")
        #expect(dropped.contains("m-1_0"), "departed cell's unique asset not evicted")
    }

    /// A stationary fill never schedules eviction (nothing unloads).
    @Test
    func fillWithoutUnloadNeverEvicts() {
        let runner = ManualCellBuildRunner()
        let streamer = Self.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Self.center)
        let grid = (-1 ... 1)
            .flatMap { x in (-1 ... 1).map { Self.coordinate(Int32(x), Int32($0)) } }
        for cell in grid {
            runner.complete(
                cell,
                with: .success(Self.cellScene(meshKeys: ["m\(cell.x)_\(cell.y)"]))
            )
        }
        for _ in 0 ..< 12 {
            streamer.update(cameraPosition: Self.center)
        }
        #expect(streamer.residentCellCount == 9)
        #expect(runner.evictedMeshKeys.isEmpty)
    }
}

extension CellStreamerTests {
    // MARK: - Camera reseed

    @Test
    func onlyTheFirstIntegratedCellReseedsTheCamera() throws {
        let runner = ManualCellBuildRunner()
        var cameras: [SceneCamera?] = []
        let streamer = Self.makeStreamer(runner: runner) { _, camera in
            cameras.append(camera)
        }
        streamer.update(cameraPosition: Self.center)

        runner.complete(Self.coordinate(0, 0), with: .success(Self.cellScene()))
        runner.complete(Self.coordinate(1, 0), with: .success(Self.cellScene()))
        streamer.update(cameraPosition: Self.center) // integrates cell 1
        streamer.update(cameraPosition: Self.center) // integrates cell 2

        try #require(cameras.count == 2)
        #expect(cameras[0] != nil) // first frames the camera
        #expect(cameras[1] == nil) // second leaves it alone
    }

    @Test
    func cameraReseedWaitsForACellWithBounds() throws {
        let runner = ManualCellBuildRunner()
        var cameras: [SceneCamera?] = []
        let streamer = Self.makeStreamer(runner: runner) { _, camera in
            cameras.append(camera)
        }
        streamer.update(cameraPosition: Self.center)

        // First integrated cell drew nothing (no bounds) -> no reseed yet.
        runner.complete(Self.coordinate(0, 0), with: .success(Self.cellScene(bounds: nil)))
        runner.complete(Self.coordinate(1, 0), with: .success(Self.cellScene()))
        streamer.update(cameraPosition: Self.center)
        streamer.update(cameraPosition: Self.center)

        try #require(cameras.count == 2)
        #expect(cameras[0] == nil) // boundless cell: no camera
        #expect(cameras[1] != nil) // first drawable cell frames it
    }
}

extension CellStreamerTests {
    @Test
    func staleSuccessfulBuildEvictsItsUnownedAssetsBeforeNextBuild() {
        let runner = ManualCellBuildRunner()
        let streamer = Self.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Self.center)
        runner.complete(Self.coordinate(0, 0), with: .success(Self.cellScene()))
        streamer.update(cameraPosition: Self.center)

        let far = CellGridManager.cellCenter(of: Self.coordinate(5, 0))
        streamer.update(cameraPosition: far)
        runner.complete(Self.coordinate(-1, 0), with: .success(Self.cellScene(
            meshKeys: ["stale-mesh"], textureKeys: ["stale-texture"]
        )))
        streamer.update(cameraPosition: far)

        #expect(runner.evictedMeshKeys.last == ["stale-mesh"])
        #expect(runner.evictedTextureKeys.last == ["stale-texture"])
        #expect(runner.enqueued.last == Self.coordinate(5, 0))
    }

    @Test
    func launchIgnoresDemoCameraUntilFirstDrawableCellSeedsCamera() {
        let runner = ManualCellBuildRunner()
        let streamer = Self.makeStreamer(runner: runner)
        let unrelatedCamera = CellGridManager.cellCenter(of: Self.coordinate(40, 40))

        streamer.update(cameraPosition: unrelatedCamera)

        #expect(runner.enqueued == [Self.coordinate(0, 0)])
    }
}
