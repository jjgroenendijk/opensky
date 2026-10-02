// Off-main cell builds. `CellSceneProvider` is the build seam (the real builder
// in the app, a fake in unit tests); `CellBuildRunning` runs builds off the main
// thread and buffers results for the streamer to poll once per frame.

import Foundation
import OpenSkyAudio
import OpenSkyCombatInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyWorldState
import Synchronization

/// Builds one cell scene by grid coordinate. The single seam scene build
/// crosses to reach `CellSceneBuilder`; a fake conformer lets CellStreamer
/// tests run without Metal or game data. Called only on the runner's serial
/// executor (never the main thread), so it inherits the single-threaded
/// confinement CellSceneBuilder / MeshLibrary / TextureLibrary require.
nonisolated public protocol CellSceneProvider {
    /// Throws `CellSceneError.cellNotFound` for a void grid slot; any other throw is
    /// a build failure. The streamer classifies both.
    /// - Parameter state: the runtime world state to build against, an immutable
    ///   value captured on the main thread.
    func buildCell(at coordinate: CellCoordinate, state: WorldStateSnapshot) throws -> CellScene

    /// Drops the given cached assets (a departed cell's keys no resident cell
    /// needs). Runs on the same executor as builds so libraries stay confined.
    func evict(droppingMeshKeys: Set<String>, droppingTextureKeys: Set<String>)

    func buildDistantLOD(
        center: CellCoordinate,
        hiddenCells: Set<CellCoordinate>
    ) throws -> DistantLODScene?

    /// Resolves + builds the destination of one placed teleport door.
    func buildDoorTransition(
        from sourceDoor: FormID,
        state: WorldStateSnapshot
    ) throws -> DoorTransition
}

nonisolated extension CellSceneProvider {
    public func buildDistantLOD(
        center _: CellCoordinate,
        hiddenCells _: Set<CellCoordinate>
    ) throws -> DistantLODScene? {
        nil
    }

    public func buildDoorTransition(
        from sourceDoor: FormID,
        state _: WorldStateSnapshot
    ) throws -> DoorTransition {
        throw CellSceneError.doorReferenceNotFound(formID: sourceDoor)
    }
}

/// Adapts `CellSceneBuilder` to the provider seam, pinning the worldspace so
/// the streamer only passes grid coordinates. The runner takes it as `sending`,
/// so the builder and its libraries live only on the build queue.
nonisolated public struct BuilderCellSceneProvider: CellSceneProvider {
    public let builder: CellSceneBuilder
    public let worldspaceEditorID: String

    public init(builder: CellSceneBuilder, worldspaceEditorID: String) {
        self.builder = builder
        self.worldspaceEditorID = worldspaceEditorID
    }

    public func buildCell(
        at coordinate: CellCoordinate,
        state: WorldStateSnapshot
    ) throws -> CellScene {
        try builder.buildScene(
            worldspaceEditorID: worldspaceEditorID,
            gridX: coordinate.x,
            gridY: coordinate.y,
            state: state
        )
    }

    public func evict(
        droppingMeshKeys meshKeys: Set<String>,
        droppingTextureKeys textureKeys: Set<String>
    ) {
        builder.meshes.evict(dropping: meshKeys)
        builder.collisionModels?.evict(dropping: meshKeys)
        builder.evictCollisionPartitions(dropping: meshKeys)
        builder.textures.evict(dropping: textureKeys)
    }

    public func buildDistantLOD(
        center: CellCoordinate,
        hiddenCells: Set<CellCoordinate>
    ) throws -> DistantLODScene? {
        try builder.buildDistantLOD(
            worldspaceEditorID: worldspaceEditorID,
            center: center,
            hiddenCells: hiddenCells
        )
    }

    public func buildDoorTransition(
        from sourceDoor: FormID,
        state: WorldStateSnapshot
    ) throws -> DoorTransition {
        try builder.buildDoorTransition(
            from: sourceDoor,
            worldspaceEditorID: worldspaceEditorID,
            state: state
        )
    }
}

/// One finished build handed back to the main-thread streamer.
nonisolated public struct CellBuildResult: Sendable {
    public let coordinate: CellCoordinate
    public let result: Result<CellScene, any Error>

    public init(
        coordinate: CellCoordinate,
        result: Result<CellScene, any Error>
    ) {
        self.coordinate = coordinate
        self.result = result
    }
}

nonisolated public struct CellBuildMetric: Equatable, Sendable {
    public let collisionDurationMS: Double
    public let collisionShapeCount: Int
    public let collisionTriangleCount: Int
    /// Actor phase accounting mirrored off CellLoadSummary so the fly bench
    /// can gate latency + exact accounting per cell (5.5).
    public var actorDurationMS = 0.0
    public var actorDiscoveredCount = 0
    public var actorRenderedCount = 0
    public var actorDisabledSkipCount = 0
    public var actorFailureCount = 0
    /// One reason per counted failure, mirrored off CellLoadSummary so the
    /// fly bench can prove every failure explained (5.6 acceptance).
    public var actorFailureReasons: [String] = []
    public var actorAnimatedCount = 0
    public var actorAnimationFailureCount = 0
    public var actorAnimationFailureReasons: [String] = []

    public var actorAccountingIsExact: Bool {
        actorDiscoveredCount
            == actorRenderedCount + actorDisabledSkipCount + actorFailureCount
    }

    public var actorFailuresAreExplained: Bool {
        actorFailureCount == actorFailureReasons.count
    }

    public var actorAnimationAccountingIsExact: Bool {
        actorRenderedCount == actorAnimatedCount + actorAnimationFailureCount
    }

    public var actorAnimationFailuresAreExplained: Bool {
        actorAnimationFailureCount == actorAnimationFailureReasons.count
    }
}

nonisolated public struct DistantLODBuildResult: Sendable {
    public let center: CellCoordinate
    public let result: Result<DistantLODScene?, any Error>
}

nonisolated public struct DoorTransitionBuildResult: Sendable {
    public let sourceDoor: FormID
    public let result: Result<DoorTransition, any Error>
}

/// Runs cell builds off the main thread and buffers the results for a
/// main-thread poll. The streamer enqueues coordinates and drains completions
/// once per frame; ordering of completions is the executor's business.
nonisolated public protocol CellBuildRunning: AnyObject {
    /// - Parameter state: the world-state snapshot the build runs against,
    ///   captured by the caller before the work leaves the main thread.
    func enqueue(_ coordinate: CellCoordinate, state: WorldStateSnapshot)
    /// Returns and clears everything finished since the last drain.
    func drainCompleted() -> [CellBuildResult]
    /// Schedules an eviction pass on the build executor (after queued builds),
    /// dropping the given assets a departed cell no longer needs.
    func enqueueEviction(droppingMeshKeys: Set<String>, droppingTextureKeys: Set<String>)
    @discardableResult
    func enqueueDistantLOD(center: CellCoordinate, hiddenCells: Set<CellCoordinate>) -> Bool
    func drainCompletedDistantLOD() -> [DistantLODBuildResult]
    func enqueueDoorTransition(from sourceDoor: FormID, state: WorldStateSnapshot)
    func drainCompletedDoorTransitions() -> [DoorTransitionBuildResult]
}

nonisolated extension CellBuildRunning {
    @discardableResult
    public func enqueueDistantLOD(
        center _: CellCoordinate,
        hiddenCells _: Set<CellCoordinate>
    ) -> Bool {
        false
    }

    public func drainCompletedDistantLOD() -> [DistantLODBuildResult] {
        []
    }

    public func enqueueDoorTransition(from _: FormID, state _: WorldStateSnapshot) {}
    public func drainCompletedDoorTransitions() -> [DoorTransitionBuildResult] {
        []
    }
}

/// Builds cells one at a time on one serial queue, off the main thread.
/// The provider arrives as `sending` and only the queue locks it, so the lock never
/// waits. Results are `Sendable` and cross in `results` (docs/engine/cell-streaming.md).
nonisolated public final class SerialCellBuildRunner: CellBuildRunning, Sendable {
    nonisolated private struct Bookkeeping {
        /// Lets the fly-path gate prove each wanted cell built once.
        var buildCounts: [CellCoordinate: Int] = [:]
        var buildMetrics: [CellCoordinate: CellBuildMetric] = [:]
        /// Queued or building. A duplicate enqueue is a no-op, which bounds the
        /// queue depth to the grid size even if the streamer has a bug.
        var pending: Set<CellCoordinate> = []
        var pendingLOD: Set<CellCoordinate> = []
        var pendingDoorTransitions: Set<FormID> = []
    }

    nonisolated private struct Results {
        var cells: [CellBuildResult] = []
        var distantLOD: [DistantLODBuildResult] = []
        var doorTransitions: [DoorTransitionBuildResult] = []
    }

    private let provider: Mutex<any CellSceneProvider>
    private let queue: DispatchQueue
    private let bookkeeping = Mutex(Bookkeeping())
    private let results = Mutex(Results())

    public init(
        provider: sending any CellSceneProvider,
        label: String = "nl.jjgroenendijk.opensky.cellbuild"
    ) {
        self.provider = Mutex(provider)
        queue = DispatchQueue(label: label, qos: .utility)
    }

    public func enqueue(_ coordinate: CellCoordinate, state: WorldStateSnapshot) {
        let isNew = bookkeeping.withLock { $0.pending.insert(coordinate).inserted }
        guard isNew else { return }
        queue.async { [self] in
            bookkeeping.withLock { $0.buildCounts[coordinate, default: 0] += 1 }
            let result = provider.withLock { provider in
                Result { try provider.buildCell(at: coordinate, state: state) }
            }
            if let metric = try? result.map(Self.metric(for:)).get() {
                bookkeeping.withLock { $0.buildMetrics[coordinate] = metric }
            }
            let entry = CellBuildResult(coordinate: coordinate, result: result)
            results.withLock { $0.cells.append(entry) }
        }
    }

    private static func metric(for scene: CellScene) -> CellBuildMetric {
        CellBuildMetric(
            collisionDurationMS: scene.staticCollision.buildDurationMS,
            collisionShapeCount: scene.staticCollision.stats.shapeCount,
            collisionTriangleCount: scene.staticCollision.stats.triangleCount,
            actorDurationMS: scene.summary.actorBuildDurationMS,
            actorDiscoveredCount: scene.summary.actorCount,
            actorRenderedCount: scene.summary.actorDrawnCount,
            actorDisabledSkipCount: scene.summary.actorDisabledSkipCount,
            actorFailureCount: scene.summary.actorFailureCount,
            actorFailureReasons: scene.summary.actorFailureReasons,
            actorAnimatedCount: scene.summary.actorAnimatedCount,
            actorAnimationFailureCount: scene.summary.actorAnimationFailureCount,
            actorAnimationFailureReasons: scene.summary.actorAnimationFailureReasons
        )
    }

    public func drainCompleted() -> [CellBuildResult] {
        let out = results.withLock { state in
            defer { state.cells.removeAll(keepingCapacity: true) }
            return state.cells
        }
        bookkeeping.withLock { $0.pending.subtract(out.map(\.coordinate)) }
        return out
    }

    public func enqueueEviction(
        droppingMeshKeys meshKeys: Set<String>,
        droppingTextureKeys textureKeys: Set<String>
    ) {
        guard !meshKeys.isEmpty || !textureKeys.isEmpty else { return }
        queue.async { [self] in
            provider.withLock {
                $0.evict(droppingMeshKeys: meshKeys, droppingTextureKeys: textureKeys)
            }
        }
    }

    @discardableResult
    public func enqueueDistantLOD(
        center: CellCoordinate,
        hiddenCells: Set<CellCoordinate>
    ) -> Bool {
        let isNew = bookkeeping.withLock { $0.pendingLOD.insert(center).inserted }
        guard isNew else { return false }
        queue.async { [self] in
            let result = provider.withLock { provider in
                Result { try provider.buildDistantLOD(center: center, hiddenCells: hiddenCells) }
            }
            let entry = DistantLODBuildResult(center: center, result: result)
            results.withLock { $0.distantLOD.append(entry) }
        }
        return true
    }

    public func drainCompletedDistantLOD() -> [DistantLODBuildResult] {
        let out = results.withLock { state in
            defer { state.distantLOD.removeAll(keepingCapacity: true) }
            return state.distantLOD
        }
        bookkeeping.withLock { $0.pendingLOD.subtract(out.map(\.center)) }
        return out
    }

    public func enqueueDoorTransition(from sourceDoor: FormID, state: WorldStateSnapshot) {
        let isNew = bookkeeping.withLock { $0.pendingDoorTransitions.insert(sourceDoor).inserted }
        guard isNew else { return }
        queue.async { [self] in
            let result = provider.withLock { provider in
                Result { try provider.buildDoorTransition(from: sourceDoor, state: state) }
            }
            let entry = DoorTransitionBuildResult(sourceDoor: sourceDoor, result: result)
            results.withLock { $0.doorTransitions.append(entry) }
        }
    }

    public func drainCompletedDoorTransitions() -> [DoorTransitionBuildResult] {
        let out = results.withLock { state in
            defer { state.doorTransitions.removeAll(keepingCapacity: true) }
            return state.doorTransitions
        }
        bookkeeping.withLock { $0.pendingDoorTransitions.subtract(out.map(\.sourceDoor)) }
        return out
    }

    /// Thread-safe snapshot for tests and scripted streaming checks.
    public func buildCountsSnapshot() -> [CellCoordinate: Int] {
        bookkeeping.withLock { $0.buildCounts }
    }

    public func buildMetricsSnapshot() -> [CellCoordinate: CellBuildMetric] {
        bookkeeping.withLock { $0.buildMetrics }
    }

    /// Blocks until every job queued so far has run. Tests use it instead of
    /// a fixed sleep. Never call it on the build queue.
    public func waitUntilIdle() {
        queue.sync {}
    }
}
