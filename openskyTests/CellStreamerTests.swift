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
nonisolated private final class ManualCellBuildRunner: CellBuildRunning {
    private(set) var enqueued: [CellCoordinate] = []
    private var ready: [CellBuildResult] = []

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
}

private enum FakeBuildError: Error { case broken }

@MainActor
struct CellStreamerTests {
    private static func coordinate(_ x: Int32, _ y: Int32) -> CellCoordinate {
        CellCoordinate(x: x, y: y)
    }

    /// Synthetic built cell: empty draw list, optional bounds (so the first
    /// integrated cell can frame a camera).
    private static func cellScene(
        bounds: (min: SIMD3<Float>, max: SIMD3<Float>)? = (SIMD3(0, 0, 0), SIMD3(10, 10, 10))
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
            bounds: bounds
        )
    }

    /// World center of cell (0,0); keeps the grid centered without recentering.
    private static let center = CellGridManager.cellCenter(of: coordinate(0, 0))

    private static func makeStreamer(
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
    func firstUpdateRequestsWholeGridOnceAndDoesNotReRequest() {
        let runner = ManualCellBuildRunner()
        let streamer = Self.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Self.center)
        #expect(runner.enqueued.count == 9) // radius 1 -> 3x3
        #expect(Set(runner.enqueued).count == 9) // no duplicates

        // Nothing completed, camera unmoved -> in-flight cells are accounted,
        // never re-requested.
        streamer.update(cameraPosition: Self.center)
        #expect(runner.enqueued.count == 9)
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

        runner.complete(Self.coordinate(1, 1), with: .failure(CellSceneError.cellNotFound(
            worldspaceEditorID: "Tamriel", gridX: 1, gridY: 1
        )))
        streamer.update(cameraPosition: Self.center)
        #expect(streamer.voidCellCount == 1)

        // Many frames later: the void slot stays accounted, no retry storm.
        for _ in 0 ..< 10 {
            streamer.update(cameraPosition: Self.center)
        }
        #expect(runner.enqueued.filter { $0 == Self.coordinate(1, 1) }.count == 1)
        #expect(streamer.voidCellCount == 1)
    }

    @Test
    func failedCellIsNeverReRequested() {
        let runner = ManualCellBuildRunner()
        let streamer = Self.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Self.center)

        runner.complete(Self.coordinate(-1, 0), with: .failure(FakeBuildError.broken))
        for _ in 0 ..< 10 {
            streamer.update(cameraPosition: Self.center)
        }
        #expect(streamer.failedCellCount == 1)
        #expect(runner.enqueued.filter { $0 == Self.coordinate(-1, 0) }.count == 1)
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

        // Recenter before any build lands: the original in-flight cells leave.
        let far = CellGridManager.cellCenter(of: Self.coordinate(5, 0))
        streamer.update(cameraPosition: far)

        // A build from the old grid lands late -> discarded, not resident.
        runner.complete(Self.coordinate(0, 0), with: .success(Self.cellScene()))
        streamer.update(cameraPosition: far)
        #expect(streamer.residentCellCount == 0)
    }

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
