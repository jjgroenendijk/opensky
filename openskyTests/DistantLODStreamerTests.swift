@testable import opensky
import simd
import Testing

nonisolated private final class LODManualRunner: CellBuildRunning {
    private var ready: [CellBuildResult] = []
    private var readyLOD: [DistantLODBuildResult] = []
    private(set) var lodRequests: [CellCoordinate] = []
    private(set) var lodHiddenCells: [Set<CellCoordinate>] = []

    func enqueue(_: CellCoordinate) {}

    func complete(_ coordinate: CellCoordinate, scene: CellScene) {
        ready.append(CellBuildResult(coordinate: coordinate, result: .success(scene)))
    }

    func drainCompleted() -> [CellBuildResult] {
        let out = ready
        ready.removeAll(keepingCapacity: true)
        return out
    }

    func enqueueEviction(droppingMeshKeys _: Set<String>, droppingTextureKeys _: Set<String>) {}

    func enqueueDistantLOD(center: CellCoordinate, hiddenCells: Set<CellCoordinate>) {
        lodRequests.append(center)
        lodHiddenCells.append(hiddenCells)
    }

    func completeLOD(_ center: CellCoordinate, scene: DistantLODScene) {
        readyLOD.append(DistantLODBuildResult(center: center, result: .success(scene)))
    }

    func drainCompletedDistantLOD() -> [DistantLODBuildResult] {
        let out = readyLOD
        readyLOD.removeAll(keepingCapacity: true)
        return out
    }
}

@MainActor
struct DistantLODStreamerTests {
    private static let center = CellCoordinate(x: 0, y: 0)

    private func cellScene() -> CellScene {
        CellScene(
            renderScene: RenderScene(instances: []),
            summary: CellLoadSummary(
                cellName: "test", gridX: 0, gridY: 0,
                totalRefCount: 0, drawnRefCount: 0,
                unsupportedBaseSkipCount: 0, markerSkipCount: 0,
                modelFailureSkipCount: 0, malformedRefSkipCount: 0,
                modelCount: 0, textureCount: 0, missingTextureCount: 0
            ),
            bounds: (SIMD3(0, 0, 0), SIMD3(1, 1, 1))
        )
    }

    @Test func waitsForFullGridThenComposesLOD() {
        let runner = LODManualRunner()
        let streamer = CellStreamer(center: Self.center, radius: 1, runner: runner) { _, _ in }
        let position = CellGridManager.cellCenter(of: Self.center)
        streamer.update(cameraPosition: position)
        #expect(runner.lodRequests.isEmpty)

        let cells = (-1 ... 1).flatMap { x in
            (-1 ... 1).map { CellCoordinate(x: Int32(x), y: Int32($0)) }
        }
        for cell in cells {
            runner.complete(cell, scene: cellScene())
        }
        for _ in cells {
            streamer.update(cameraPosition: position)
        }
        #expect(runner.lodRequests == [Self.center])
        #expect(runner.lodHiddenCells == [Set(cells)])

        runner.completeLOD(Self.center, scene: DistantLODScene(
            renderScene: RenderScene(instances: []),
            assets: CellAssets(meshKeys: ["lod"], textureKeys: []),
            blockCount: 7,
            missingBlockCount: 0
        ))
        streamer.update(cameraPosition: position)
        #expect(streamer.distantLODBlockCount == 7)

        let moved = CellGridManager.cellCenter(of: CellCoordinate(x: 3, y: 0))
        streamer.update(cameraPosition: moved)
        #expect(streamer.isCoverageTransitionActive)
        #expect(streamer.composedCellCount == 9)
        #expect(streamer.residentCellCount == 0)
        #expect(streamer.distantLODBlockCount == 7)

        let movedCells = (2 ... 4).flatMap { x in
            (-1 ... 1).map { CellCoordinate(x: Int32(x), y: Int32($0)) }
        }
        for cell in movedCells {
            runner.complete(cell, scene: cellScene())
        }
        for _ in movedCells {
            streamer.update(cameraPosition: moved)
        }
        #expect(runner.lodRequests == [Self.center, CellCoordinate(x: 3, y: 0)])
        #expect(runner.lodHiddenCells.last == Set(movedCells))
        #expect(streamer.isCoverageTransitionActive)
        #expect(streamer.composedCellCount == 9)
        #expect(streamer.distantLODBlockCount == 7)

        runner.completeLOD(CellCoordinate(x: 3, y: 0), scene: DistantLODScene(
            renderScene: RenderScene(instances: []),
            assets: CellAssets(meshKeys: ["next-lod"], textureKeys: []),
            blockCount: 8,
            missingBlockCount: 0
        ))
        streamer.update(cameraPosition: moved)
        #expect(!streamer.isCoverageTransitionActive)
        #expect(streamer.composedCellCount == 9)
        #expect(streamer.distantLODBlockCount == 8)
    }
}
