// The benchmark's route mode: the walk route, timed per cell build. The walk
// benchmark owns the route and its gates; this file adds the timing.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyRendering
import OpenSkyWorldState
import Synchronization

/// Build times reported from the build queue and read on the main actor.
nonisolated final class CellLoadLog: Sendable {
    private let loads = Mutex<[BenchmarkCellLoad]>([])

    /// An error that `ignoring` accepts is not a build, so it leaves no entry.
    func time<T>(
        _ label: String,
        ignoring: (any Error) -> Bool = { _ in false },
        _ build: () throws -> T
    ) rethrows -> T {
        let started = DispatchTime.now().uptimeNanoseconds
        do {
            let value = try build()
            append(label, started: started, error: nil)
            return value
        } catch {
            if !ignoring(error) {
                append(label, started: started, error: String(describing: error))
            }
            throw error
        }
    }

    var snapshot: [BenchmarkCellLoad] {
        loads.withLock { $0 }
    }

    private func append(_ label: String, started: UInt64, error: String?) {
        let elapsedMS = Double(DispatchTime.now().uptimeNanoseconds - started) / 1e6
        let load = BenchmarkCellLoad(label: label, totalMS: elapsedMS, error: error)
        loads.withLock { $0.append(load) }
    }
}

/// Times each build of the wrapped provider.
nonisolated struct TimedCellSceneProvider: CellSceneProvider {
    let base: any CellSceneProvider
    let worldspace: String
    let log: CellLoadLog

    func buildCell(at coordinate: CellCoordinate, state: WorldStateSnapshot) throws -> CellScene {
        try log.time(
            "\(worldspace) (\(coordinate.x),\(coordinate.y))",
            ignoring: Self.isVoidSlot
        ) {
            try base.buildCell(at: coordinate, state: state)
        }
    }

    private static func isVoidSlot(_ error: any Error) -> Bool {
        if case .cellNotFound? = error as? CellSceneError {
            return true
        }
        return false
    }

    func evict(droppingMeshKeys: Set<String>, droppingTextureKeys: Set<String>) {
        base.evict(droppingMeshKeys: droppingMeshKeys, droppingTextureKeys: droppingTextureKeys)
    }

    func buildDistantLOD(
        center: CellCoordinate,
        hiddenCells: Set<CellCoordinate>
    ) throws -> DistantLODScene? {
        try log.time("distant LOD (\(center.x),\(center.y))") {
            try base.buildDistantLOD(center: center, hiddenCells: hiddenCells)
        }
    }

    func buildDoorTransition(
        from sourceDoor: FormID,
        state: WorldStateSnapshot
    ) throws -> DoorTransition {
        try log.time("door \(sourceDoor)") {
            try base.buildDoorTransition(from: sourceDoor, state: state)
        }
    }

    func loadActorProp(_ request: ActorPropRequest) throws -> RenderModel {
        try base.loadActorProp(request)
    }
}

@MainActor
public enum PerformanceBenchmarkRoute {
    /// Walks the shared route with `provider`, which should start with empty caches.
    /// Throws when the walk misses one of its gates.
    public static func run(
        renderer: Renderer,
        provider: sending any CellSceneProvider,
        worldspace: String,
        plan: PerformanceBenchmarkPlan,
        maxFrames: Int = 36000
    ) throws -> BenchmarkRoute {
        let log = CellLoadLog()
        let walk = try CellStreamingWalkBenchmark.run(
            renderer: renderer,
            provider: TimedCellSceneProvider(base: provider, worldspace: worldspace, log: log),
            configuration: CellStreamingWalkBenchmarkConfiguration(
                size: (plan.frameWidth, plan.frameHeight),
                maxFrames: maxFrames
            )
        )
        return BenchmarkRoute(
            frameTime: BenchmarkTimeStats(milliseconds: walk.render.frameMS)
                ?? BenchmarkTimeStats(frames: 0, averageMS: 0, percentile95MS: 0, worstMS: 0),
            gpuTime: BenchmarkTimeStats(milliseconds: walk.render.gpuMS),
            cellLoads: log.snapshot
        )
    }
}
