// CellStreamer: request dedupe, no retry on void or failed cells, one
// recompose per frame, unload on recenter, out-of-order completion, and first-
// cell camera reseed. Fixture: `Tests/TestSupport/World/Streaming/CellStreamerFixture.swift`.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import OpenSkyWorldTesting
import simd
import Testing

private typealias Fixture = CellStreamerFixture

private enum FakeBuildError: Error { case broken }

@MainActor
struct CellStreamerTests {
    // MARK: - Request dedupe

    @Test
    func firstUpdateSubmitsOneBuildAndQueuesRestWithoutDuplicates() {
        let runner = ManualCellBuildRunner()
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Fixture.center)
        #expect(runner.enqueued == [Fixture.coordinate(0, 0)])
        #expect(streamer.queuedRequestCount == 8)
        #expect(streamer.inFlightCellCount == 9)

        // Nothing completed -> no second build reaches the runner.
        streamer.update(cameraPosition: Fixture.center)
        #expect(runner.enqueued.count == 1)
    }

    @Test
    func centerCellIsRequestedFirst() {
        let runner = ManualCellBuildRunner()
        let streamer = Fixture.makeStreamer(runner: runner, radius: 2)
        streamer.update(cameraPosition: Fixture.center)
        #expect(runner.enqueued.first == Fixture.coordinate(0, 0))
    }

    // MARK: - No-retry bookkeeping

    @Test
    func voidCellIsNeverReRequested() {
        let runner = ManualCellBuildRunner()
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Fixture.center)

        runner.complete(Fixture.coordinate(0, 0), with: .failure(CellSceneError.cellNotFound(
            worldspaceEditorID: "Tamriel", gridX: 0, gridY: 0
        )))
        streamer.update(cameraPosition: Fixture.center)
        #expect(streamer.voidCellCount == 1)

        // Many frames later: the void slot stays accounted, no retry storm.
        for _ in 0 ..< 10 {
            streamer.update(cameraPosition: Fixture.center)
        }
        #expect(runner.enqueued.filter { $0 == Fixture.coordinate(0, 0) }.count == 1)
        #expect(streamer.voidCellCount == 1)
    }

    @Test
    func failedCellIsNeverReRequested() {
        let runner = ManualCellBuildRunner()
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Fixture.center)

        runner.complete(Fixture.coordinate(0, 0), with: .failure(FakeBuildError.broken))
        for _ in 0 ..< 10 {
            streamer.update(cameraPosition: Fixture.center)
        }
        #expect(streamer.failedCellCount == 1)
        #expect(runner.enqueued.filter { $0 == Fixture.coordinate(0, 0) }.count == 1)
    }

    // MARK: - Integration budget

    @Test
    func integratesAtMostOneCellPerFrame() {
        let runner = ManualCellBuildRunner()
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Fixture.center)

        // Three drawable cells finish at once.
        for cell in [Fixture.coordinate(0, 0), Fixture.coordinate(1, 0), Fixture.coordinate(
            -1,
            0
        )] {
            runner.complete(cell, with: .success(Fixture.cellScene()))
        }
        streamer.update(cameraPosition: Fixture.center)
        #expect(streamer.residentCellCount == 1)
        streamer.update(cameraPosition: Fixture.center)
        #expect(streamer.residentCellCount == 2)
        streamer.update(cameraPosition: Fixture.center)
        #expect(streamer.residentCellCount == 3)
        #expect(streamer.pendingCompletionCount == 0)
    }

    @Test
    func voidAndFailedDoNotConsumeTheIntegrationBudget() {
        let runner = ManualCellBuildRunner()
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Fixture.center)

        // A void, a failure, then a drawable cell -- cheap outcomes drain
        // freely, the drawable one still integrates the same frame.
        runner.complete(Fixture.coordinate(1, 1), with: .failure(CellSceneError.cellNotFound(
            worldspaceEditorID: "Tamriel", gridX: 1, gridY: 1
        )))
        runner.complete(Fixture.coordinate(-1, -1), with: .failure(FakeBuildError.broken))
        runner.complete(Fixture.coordinate(0, 0), with: .success(Fixture.cellScene()))
        streamer.update(cameraPosition: Fixture.center)
        #expect(streamer.residentCellCount == 1)
        #expect(streamer.voidCellCount == 1)
        #expect(streamer.failedCellCount == 1)
    }

    // MARK: - Out-of-order completions

    @Test
    func outOfOrderCompletionsAllIntegrate() {
        let runner = ManualCellBuildRunner()
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Fixture.center)

        // In-grid cells (radius 1), delivered in a non-dispatch order.
        let cells = [Fixture.coordinate(1, 1), Fixture.coordinate(0, 0), Fixture.coordinate(-1, 1)]
        for cell in cells {
            runner.complete(cell, with: .success(Fixture.cellScene()))
        }
        // One per frame regardless of delivery order.
        for _ in cells {
            streamer.update(cameraPosition: Fixture.center)
        }
        #expect(streamer.residentCellCount == 3)
    }

    // MARK: - Unload on recenter

    @Test
    func recenterUnloadsCellsThatLeftTheGrid() {
        let runner = ManualCellBuildRunner()
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Fixture.center)

        // Resolve the whole 3x3 as drawable.
        let grid = (-1 ... 1)
            .flatMap { x in (-1 ... 1).map { Fixture.coordinate(Int32(x), Int32($0)) } }
        for cell in grid {
            runner.complete(cell, with: .success(Fixture.cellScene()))
        }
        for _ in grid {
            streamer.update(cameraPosition: Fixture.center)
        }
        #expect(streamer.residentCellCount == 9)

        // Jump far away: every old cell leaves the grid -> all dropped.
        let far = CellGridManager.cellCenter(of: Fixture.coordinate(5, 0))
        streamer.update(cameraPosition: far)
        #expect(streamer.residentCellCount == 0)
        // And a fresh 3x3 gets requested around the new center.
        #expect(runner.enqueued.filter { $0 == Fixture.coordinate(5, 0) }.count == 1)
    }

    @Test
    func staleCompletionAfterUnloadIsDropped() {
        let runner = ManualCellBuildRunner()
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Fixture.center)

        // Seed the real camera, then let the next submitted neighbor remain
        // active while that camera recenters far away.
        runner.complete(Fixture.coordinate(0, 0), with: .success(Fixture.cellScene()))
        streamer.update(cameraPosition: Fixture.center)

        let far = CellGridManager.cellCenter(of: Fixture.coordinate(5, 0))
        streamer.update(cameraPosition: far)

        // A build from the old grid lands late -> discarded, not resident.
        runner.complete(Fixture.coordinate(-1, 0), with: .success(Fixture.cellScene()))
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
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Fixture.center)

        let grid = (-1 ... 1)
            .flatMap { x in (-1 ... 1).map { Fixture.coordinate(Int32(x), Int32($0)) } }
        for cell in grid {
            runner.complete(cell, with: .success(Fixture.cellScene(
                meshKeys: ["m\(cell.x)_\(cell.y)"], textureKeys: ["t\(cell.x)_\(cell.y)"]
            )))
        }
        for _ in grid {
            streamer.update(cameraPosition: Fixture.center)
        }
        #expect(streamer.residentCellCount == 9)

        // Far jump: disjoint new grid, so the whole old grid is dropped.
        streamer.update(cameraPosition: CellGridManager.cellCenter(of: Fixture.coordinate(9, 0)))
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
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Fixture.center)

        let grid = (-1 ... 1)
            .flatMap { x in (-1 ... 1).map { Fixture.coordinate(Int32(x), Int32($0)) } }
        for cell in grid {
            // Every cell shares "common"; each also has a unique key.
            runner.complete(cell, with: .success(Fixture.cellScene(
                meshKeys: ["m\(cell.x)_\(cell.y)", "common"]
            )))
        }
        for _ in grid {
            streamer.update(cameraPosition: Fixture.center)
        }

        // One cell east: unloads the x = -1 column only; x = 0/1 stay resident
        // and still use "common".
        streamer.update(cameraPosition: CellGridManager.cellCenter(of: Fixture.coordinate(1, 0)))
        let dropped = runner.evictedMeshKeys.last ?? []
        #expect(!dropped.contains("common"), "shared asset evicted while still in use")
        #expect(dropped.contains("m-1_0"), "departed cell's unique asset not evicted")
    }

    /// A stationary fill never schedules eviction (nothing unloads).
    @Test
    func fillWithoutUnloadNeverEvicts() {
        let runner = ManualCellBuildRunner()
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Fixture.center)
        let grid = (-1 ... 1)
            .flatMap { x in (-1 ... 1).map { Fixture.coordinate(Int32(x), Int32($0)) } }
        for cell in grid {
            runner.complete(
                cell,
                with: .success(Fixture.cellScene(meshKeys: ["m\(cell.x)_\(cell.y)"]))
            )
        }
        for _ in 0 ..< 12 {
            streamer.update(cameraPosition: Fixture.center)
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
        let streamer = Fixture.makeStreamer(runner: runner) { _, camera in
            cameras.append(camera)
        }
        streamer.update(cameraPosition: Fixture.center)

        runner.complete(Fixture.coordinate(0, 0), with: .success(Fixture.cellScene()))
        runner.complete(Fixture.coordinate(1, 0), with: .success(Fixture.cellScene()))
        streamer.update(cameraPosition: Fixture.center) // integrates cell 1
        streamer.update(cameraPosition: Fixture.center) // integrates cell 2

        try #require(cameras.count == 2)
        #expect(cameras[0] != nil) // first frames the camera
        #expect(cameras[1] == nil) // second leaves it alone
    }

    @Test
    func cameraReseedWaitsForACellWithBounds() throws {
        let runner = ManualCellBuildRunner()
        var cameras: [SceneCamera?] = []
        let streamer = Fixture.makeStreamer(runner: runner) { _, camera in
            cameras.append(camera)
        }
        streamer.update(cameraPosition: Fixture.center)

        // First integrated cell drew nothing (no bounds) -> no reseed yet.
        runner.complete(Fixture.coordinate(0, 0), with: .success(Fixture.cellScene(bounds: nil)))
        runner.complete(Fixture.coordinate(1, 0), with: .success(Fixture.cellScene()))
        streamer.update(cameraPosition: Fixture.center)
        streamer.update(cameraPosition: Fixture.center)

        try #require(cameras.count == 2)
        #expect(cameras[0] == nil) // boundless cell: no camera
        #expect(cameras[1] != nil) // first drawable cell frames it
    }
}

extension CellStreamerTests {
    @Test
    func staleSuccessfulBuildEvictsItsUnownedAssetsBeforeNextBuild() {
        let runner = ManualCellBuildRunner()
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Fixture.center)
        runner.complete(Fixture.coordinate(0, 0), with: .success(Fixture.cellScene()))
        streamer.update(cameraPosition: Fixture.center)

        let far = CellGridManager.cellCenter(of: Fixture.coordinate(5, 0))
        streamer.update(cameraPosition: far)
        runner.complete(Fixture.coordinate(-1, 0), with: .success(Fixture.cellScene(
            meshKeys: ["stale-mesh"], textureKeys: ["stale-texture"]
        )))
        streamer.update(cameraPosition: far)

        #expect(runner.evictedMeshKeys.last == ["stale-mesh"])
        #expect(runner.evictedTextureKeys.last == ["stale-texture"])
        #expect(runner.enqueued.last == Fixture.coordinate(5, 0))
    }

    @Test
    func launchIgnoresDemoCameraUntilFirstDrawableCellSeedsCamera() {
        let runner = ManualCellBuildRunner()
        let streamer = Fixture.makeStreamer(runner: runner)
        let unrelatedCamera = CellGridManager.cellCenter(of: Fixture.coordinate(40, 40))

        streamer.update(cameraPosition: unrelatedCamera)

        #expect(runner.enqueued == [Fixture.coordinate(0, 0)])
    }
}

// MARK: - Actor streaming lifecycle (5.5)

extension CellStreamerTests {
    /// Actor body/head model keys ride the same per-cell asset lifecycle as
    /// statics (5.5 actor streaming): a departed cell's unique actor mesh is
    /// evicted, a body mesh shared with a still-resident cell survives.
    /// (Skeletons never enter cell assets — MeshLibrary retains them.)
    @Test
    func actorAssetsEvictWithTheirCellAndSharedBodiesSurvive() {
        let runner = ManualCellBuildRunner()
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Fixture.center)

        let grid = (-1 ... 1)
            .flatMap { x in (-1 ... 1).map { Fixture.coordinate(Int32(x), Int32($0)) } }
        for cell in grid {
            runner.complete(cell, with: .success(Fixture.cellScene(
                meshKeys: ["actor-body-shared", "actor-head-\(cell.x)_\(cell.y)"]
            )))
        }
        for _ in grid {
            streamer.update(cameraPosition: Fixture.center)
        }

        streamer.update(cameraPosition: CellGridManager.cellCenter(of: Fixture.coordinate(1, 0)))
        let dropped = runner.evictedMeshKeys.last ?? []
        #expect(!dropped.contains("actor-body-shared"), "shared actor body evicted in use")
        #expect(dropped.contains("actor-head--1_0"), "departed actor asset not evicted")
    }
}
