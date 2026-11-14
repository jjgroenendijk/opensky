@testable import OpenSkyCells
@testable import OpenSkyFormatsCore
import OpenSkyFormatsESM
@testable import OpenSkyRendering
@testable import OpenSkyTerrain
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import simd
import Testing

nonisolated private final class LODManualRunner: CellBuildRunning {
    private var ready: [CellBuildResult] = []
    private var readyLOD: [DistantLODBuildResult] = []
    private(set) var lodRequests: [CellCoordinate] = []
    private(set) var lodHiddenCells: [Set<CellCoordinate>] = []
    var prebuilds = false
    private(set) var prebuildRequests: [(CellCoordinate, Set<CellCoordinate>)] = []

    func enqueue(_: CellCoordinate, state _: WorldStateSnapshot) {}

    func complete(_ coordinate: CellCoordinate, scene: CellScene) {
        ready.append(CellBuildResult(coordinate: coordinate, result: .success(scene)))
    }

    func drainCompleted() -> [CellBuildResult] {
        let out = ready
        ready.removeAll(keepingCapacity: true)
        return out
    }

    func enqueueEviction(droppingMeshKeys _: Set<String>, droppingTextureKeys _: Set<String>) {}

    @discardableResult
    func enqueueDistantLOD(
        center: CellCoordinate, hiddenCells: Set<CellCoordinate>, state _: WorldStateSnapshot
    ) -> Bool {
        lodRequests.append(center)
        lodHiddenCells.append(hiddenCells)
        return true
    }

    func startDistantLODPrebuild(center: CellCoordinate, hiddenCells: Set<CellCoordinate>) -> Bool {
        guard prebuilds else { return false }
        prebuildRequests.append((center, hiddenCells))
        return true
    }

    /// Finishes the newest ring requested for `center`, a prebuild included.
    func completeLOD(_ center: CellCoordinate, scene: DistantLODScene) {
        readyLOD.append(DistantLODBuildResult(
            center: center, result: .success(scene), hiddenCells: hiddenCells(of: center)
        ))
    }

    func failLOD(_ center: CellCoordinate) {
        readyLOD.append(DistantLODBuildResult(
            center: center, result: .failure(LODTestError()), hiddenCells: hiddenCells(of: center)
        ))
    }

    private func hiddenCells(of center: CellCoordinate) -> Set<CellCoordinate> {
        if let index = lodRequests.lastIndex(of: center) {
            return lodHiddenCells[index]
        }
        for (requested, hidden) in prebuildRequests.reversed() where requested == center {
            return hidden
        }
        return []
    }

    func drainCompletedDistantLOD() -> [DistantLODBuildResult] {
        let out = readyLOD
        readyLOD.removeAll(keepingCapacity: true)
        return out
    }
}

private struct LODTestError: Error {}

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

    @Test func thePrebuiltFirstRingStartsWithTheGridAndIsNotBuiltTwice() {
        let runner = LODManualRunner()
        runner.prebuilds = true
        let streamer = CellStreamer(center: Self.center, radius: 1, runner: runner) { _, _ in }
        let position = CellGridManager.cellCenter(of: Self.center)
        streamer.update(cameraPosition: position)
        let cells = Set((-1 ... 1).flatMap { x in
            (-1 ... 1).map { CellCoordinate(x: Int32(x), y: Int32($0)) }
        })
        #expect(runner.prebuildRequests.map(\.0) == [Self.center])
        #expect(runner.prebuildRequests.first?.1 == cells)

        runner.completeLOD(Self.center, scene: DistantLODScene(
            renderScene: RenderScene(instances: []),
            assets: CellAssets(),
            blockCount: 5,
            missingBlockCount: 0
        ))
        streamer.update(cameraPosition: position)
        #expect(!streamer.coverage.startAreaReady)
        for cell in cells {
            runner.complete(cell, scene: cellScene())
        }
        for _ in cells {
            streamer.update(cameraPosition: position)
        }
        #expect(streamer.coverage.startAreaReady)
        #expect(streamer.coverage.distantLODBlockCount == 5)
        #expect(runner.lodRequests.isEmpty)
        #expect(runner.prebuildRequests.count == 1)
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
        #expect(streamer.coverage.distantLODBlockCount == 7)

        let moved = CellGridManager.cellCenter(of: CellCoordinate(x: 3, y: 0))
        streamer.update(cameraPosition: moved)
        #expect(streamer.coverage.isCoverageTransitionActive)
        #expect(streamer.coverage.composedCellCount == 9)
        #expect(streamer.coverage.residentCellCount == 0)
        #expect(streamer.coverage.distantLODBlockCount == 7)

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
        #expect(streamer.coverage.isCoverageTransitionActive)
        #expect(streamer.coverage.composedCellCount == 9)
        #expect(streamer.coverage.distantLODBlockCount == 7)

        runner.completeLOD(CellCoordinate(x: 3, y: 0), scene: DistantLODScene(
            renderScene: RenderScene(instances: []),
            assets: CellAssets(meshKeys: ["next-lod"], textureKeys: []),
            blockCount: 8,
            missingBlockCount: 0
        ))
        streamer.update(cameraPosition: moved)
        #expect(!streamer.coverage.isCoverageTransitionActive)
        #expect(streamer.coverage.composedCellCount == 9)
        #expect(streamer.coverage.distantLODBlockCount == 8)
    }

    private func loadNearGrid(
        _ streamer: CellStreamer, runner: LODManualRunner, position: SIMD3<Float>
    ) {
        let cells = (-1 ... 1).flatMap { x in
            (-1 ... 1).map { CellCoordinate(x: Int32(x), y: Int32($0)) }
        }
        for cell in cells {
            runner.complete(cell, scene: cellScene())
        }
        for _ in cells {
            streamer.update(cameraPosition: position)
        }
    }

    @Test func startAreaWaitsForTheFirstDistantRing() {
        let runner = LODManualRunner()
        let streamer = CellStreamer(center: Self.center, radius: 1, runner: runner) { _, _ in }
        let position = CellGridManager.cellCenter(of: Self.center)
        streamer.update(cameraPosition: position)
        #expect(!streamer.coverage.startAreaReady)

        loadNearGrid(streamer, runner: runner, position: position)
        #expect(streamer.coverage.nearGridResolved)
        #expect(!streamer.coverage.startAreaReady, "the near grid alone leaves bare sky beyond it")

        runner.completeLOD(Self.center, scene: DistantLODScene(
            renderScene: RenderScene(instances: []),
            assets: CellAssets(meshKeys: ["lod"], textureKeys: []),
            blockCount: 7,
            missingBlockCount: 0
        ))
        streamer.update(cameraPosition: position)
        #expect(streamer.coverage.startAreaReady)
    }

    @Test func aQuickFirstRingReadiesTheStartAreaAndIsBuiltAgain() {
        let runner = LODManualRunner()
        runner.prebuilds = true
        let streamer = CellStreamer(center: Self.center, radius: 1, runner: runner) { _, _ in }
        let position = CellGridManager.cellCenter(of: Self.center)
        streamer.update(cameraPosition: position)
        runner.completeLOD(Self.center, scene: DistantLODScene(
            renderScene: RenderScene(instances: []),
            assets: CellAssets(),
            blockCount: 5,
            missingBlockCount: 0,
            largeReferencesPending: true
        ))
        loadNearGrid(streamer, runner: runner, position: position)
        streamer.update(cameraPosition: position)
        #expect(runner.lodRequests == [Self.center], "the full ring is still built")
        #expect(
            streamer.coverage.startAreaReady,
            "the cover must not wait for the generated terrain and the large references"
        )

        runner.completeLOD(Self.center, scene: DistantLODScene(
            renderScene: RenderScene(instances: []),
            assets: CellAssets(),
            blockCount: 5,
            missingBlockCount: 0
        ))
        streamer.update(cameraPosition: position)
        #expect(streamer.coverage.startAreaReady)
        #expect(streamer.composition.distantLOD?.largeReferencesPending == false)
        #expect(streamer.coverage.nearGridResolved, "the swap keeps the near grid drawn")
    }

    @Test func anEnableChangeOfARingReferenceBuildsTheRingAgain() {
        let runner = LODManualRunner()
        let streamer = CellStreamer(center: Self.center, radius: 1, runner: runner) { _, _ in }
        let position = CellGridManager.cellCenter(of: Self.center)
        streamer.update(cameraPosition: position)
        loadNearGrid(streamer, runner: runner, position: position)
        runner.completeLOD(Self.center, scene: DistantLODScene(
            renderScene: RenderScene(instances: []),
            assets: CellAssets(),
            blockCount: 1,
            missingBlockCount: 0
        ).watching([0x0012_3456]))
        streamer.update(cameraPosition: position)
        #expect(runner.lodRequests == [Self.center])

        streamer.runtimeStates.noteEnableParentMutation(
            .plugin(name: "Other.esp", objectID: 0x99),
            sequence: 1
        )
        streamer.update(cameraPosition: position)
        #expect(runner.lodRequests == [Self.center])

        streamer.runtimeStates.noteEnableParentMutation(
            .plugin(name: "Skyrim.esm", objectID: 0x0012_3456), sequence: 2
        )
        streamer.update(cameraPosition: position)
        #expect(runner.lodRequests == [Self.center, Self.center])
    }

    @Test func aFailedDistantRingStillReadiesTheStartArea() {
        let runner = LODManualRunner()
        let streamer = CellStreamer(center: Self.center, radius: 1, runner: runner) { _, _ in }
        let position = CellGridManager.cellCenter(of: Self.center)
        streamer.update(cameraPosition: position)
        loadNearGrid(streamer, runner: runner, position: position)

        runner.failLOD(Self.center)
        streamer.update(cameraPosition: position)
        #expect(streamer.coverage.startAreaReady)
    }
}
