// The cold and warm load of the tour's first scene, off the main actor. A new
// builder with empty caches builds the scene's cells twice: once cold, then
// again with its caches full. The live streamer is not touched.

import Foundation
import Metal
import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering
import OpenSkyTerrain

nonisolated public struct BenchmarkLoadInputs: Sendable {
    public let root: GameDataRoot
    public let device: any MTLDevice
    public let terrainLOD: TerrainLODConfigurationStore

    public init(
        root: GameDataRoot,
        device: any MTLDevice,
        terrainLOD: TerrainLODConfigurationStore
    ) {
        self.root = root
        self.device = device
        self.terrainLOD = terrainLOD
    }
}

nonisolated public enum BenchmarkLoadPasses {
    /// The setup opens the load order and the archives anew, so the cold pass shares no cache.
    /// An exterior builds the 3 by 3 block around its origin and the distant LOD around it.
    @concurrent
    public static func run(
        place: BenchmarkPlace, inputs: BenchmarkLoadInputs
    ) async throws -> (cold: BenchmarkLoadPass, warm: BenchmarkLoadPass) {
        let recorder = LoadPhaseRecorder()
        let started = DispatchTime.now().uptimeNanoseconds
        let loadOrder = try ActiveLoadOrder.open(root: inputs.root)
        let builder = try ColdCellBuilder.makeBuilder(
            loadOrder: loadOrder, files: VirtualFileSystem(root: inputs.root),
            device: inputs.device,
            recorder: recorder, terrainLOD: inputs.terrainLOD
        )
        let setupMS = milliseconds(since: started)
        let coldCells = pass(place: place, builder: builder, plugins: loadOrder.plugins)
        let coldMS = milliseconds(since: started)
        let cold = BenchmarkLoadPass(
            totalMS: coldMS, setupMS: setupMS,
            phases: recorder.snapshot().completed(totalMS: coldMS), cells: coldCells
        )
        recorder.reset()
        let warmStart = DispatchTime.now().uptimeNanoseconds
        let warmCells = pass(place: place, builder: builder, plugins: loadOrder.plugins)
        let warmMS = milliseconds(since: warmStart)
        let warm = BenchmarkLoadPass(
            totalMS: warmMS, setupMS: 0,
            phases: recorder.snapshot().completed(totalMS: warmMS), cells: warmCells
        )
        return (cold, warm)
    }

    static func block(around x: Float, _ y: Float) -> [CellCoordinate] {
        let center = CellCoordinate(containing: SIMD3(x, y, 0))
        return (-1 ... 1).flatMap { dy in
            (-1 ... 1).map { dx in CellCoordinate(x: center.x + dx, y: center.y + dy) }
        }
    }

    private static func pass(
        place: BenchmarkPlace, builder: CellSceneBuilder, plugins: LoadOrderPlugins
    ) -> [BenchmarkCellLoad] {
        switch place {
        case let .exterior(worldspace, x, y):
            let cells = block(around: x, y)
            var loads = cells.map { cell in
                timed("\(worldspace) (\(cell.x),\(cell.y))") {
                    try builder.textures.batchLoads {
                        _ = try builder.buildScene(
                            worldspaceEditorID: worldspace, gridX: cell.x, gridY: cell.y
                        )
                    }
                }
            }
            loads.append(timed("distant LOD") {
                try builder.textures.batchLoads {
                    _ = try builder.buildDistantLOD(
                        worldspaceEditorID: worldspace,
                        center: CellCoordinate(containing: SIMD3(x, y, 0)),
                        hiddenCells: Set(cells)
                    )
                }
            })
            return loads
        case let .interior(cell):
            return [timed("interior \(cell)") {
                guard
                    case let .interior(formID, _)? = CellDirectory.find(
                        editorID: cell, in: plugins
                    )
                else {
                    throw BenchmarkLoadPassError.noInterior(cell)
                }
                try builder.textures.batchLoads {
                    _ = try builder.buildInteriorScene(cellFormID: formID)
                }
            }]
        }
    }

    private static func timed(_ label: String, _ build: () throws -> Void) -> BenchmarkCellLoad {
        let started = DispatchTime.now().uptimeNanoseconds
        do {
            try build()
            return BenchmarkCellLoad(label: label, totalMS: milliseconds(since: started))
        } catch {
            return BenchmarkCellLoad(
                label: label, totalMS: milliseconds(since: started),
                error: String(describing: error)
            )
        }
    }

    static func milliseconds(since started: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - started) / 1e6
    }
}

nonisolated enum BenchmarkLoadPassError: Error, CustomStringConvertible {
    case noInterior(String)

    var description: String {
        switch self {
        case let .noInterior(cell): "no interior cell '\(cell)' in the load order"
        }
    }
}
