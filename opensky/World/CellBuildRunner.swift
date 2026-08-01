// Off-main cell build execution (todo 3.2 async build): the serial-executor
// half of streaming. CellSceneProvider is the build seam (real builder in the
// app, a fake in unit tests); CellBuildRunning runs builds off the main thread
// and buffers their results for the main-thread streamer to poll once per
// frame. Concurrency confinement decision: docs/engine/cell-streaming.md.

import Foundation

/// Builds one cell scene by grid coordinate. The single seam scene build
/// crosses to reach `CellSceneBuilder`; a fake conformer lets CellStreamer
/// tests run without Metal or game data. Called only on the runner's serial
/// executor (never the main thread), so it inherits the single-threaded
/// confinement CellSceneBuilder / MeshLibrary / TextureLibrary require.
nonisolated protocol CellSceneProvider {
    /// Throws `CellSceneError.cellNotFound` for a void grid slot; any other
    /// throw is a build failure. Both are classified by the streamer.
    ///
    /// - Parameter state: the runtime world state to build against (issue
    ///   #160). It is an immutable value captured on the main thread, which is
    ///   the only way store state reaches this executor.
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
    func buildDistantLOD(
        center _: CellCoordinate,
        hiddenCells _: Set<CellCoordinate>
    ) throws -> DistantLODScene? {
        nil
    }

    func buildDoorTransition(
        from sourceDoor: FormID,
        state _: WorldStateSnapshot
    ) throws -> DoorTransition {
        throw CellSceneError.doorReferenceNotFound(formID: sourceDoor)
    }
}

/// Optional weather runtime a provider can expose (M7.2.2). GameViewController
/// pulls it off the provider to hand the renderer. Built once at setup from the
/// same ESM data, then read-only value types — safe to share to the main thread.
nonisolated protocol WeatherProviding {
    var weatherSystem: WeatherSystem? { get }
}

/// Optional GLOB index a provider can expose (issue #165). GameViewController
/// pairs it with the session's `WorldStateStore` to build the
/// `GlobalResolution` conditions, the clock and weather-chance selection read
/// global values through.
nonisolated protocol GlobalDataProviding {
    var globalStore: GlobalStore? { get }
}

/// Optional item + container indexes a provider can expose (issue #177).
/// `GameViewController` pairs the resolver with the session's
/// `WorldStateStore` to build the `InventoryRuntime` that take, drop and
/// container sessions run on. Immutable after `init` like every other `*Store`
/// here, so reading it from the main thread does not break the builder's queue
/// confinement.
nonisolated protocol ItemDataProviding {
    var inventoryBaselines: InventoryBaselineResolver? { get }
    /// Slot and model data for equippable items (issue #178), paired with the
    /// baselines above to build the session's `EquipmentRuntime`. Separate
    /// from the baseline resolver because equipping needs body templates the
    /// inventory view deliberately does not carry.
    var equipmentCatalog: EquipmentCatalog? { get }
}

/// Optional script-loading seam a provider can expose (issue #171). The
/// Papyrus world runtime resolves a script name to compiled bytecode lazily
/// through the file system, and resolves the FormIDs a VMAD property names
/// with the same master table the cell build used, so a script and the cell
/// it is attached to agree on reference identity.
///
/// Both values are immutable and thread-safe (`VirtualFileSystem` is
/// `Sendable`; `FormIDResolver` is a value), so reading them from the main
/// thread does not break the builder's queue confinement.
nonisolated protocol ScriptDataProviding {
    var scriptFileSystem: VirtualFileSystem? { get }
    var scriptFormIDResolver: FormIDResolver { get }
}

/// Optional immutable player-movement tuning resolved from active GMST data.
nonisolated protocol MovementConfigurationProviding {
    var movementConfiguration: PlayerMovementConfiguration { get }
}

/// Optional barter price factors resolved from active GMST data (issue #179).
/// Separate from `MovementConfigurationProviding` for the same reason the item
/// indexes are separate from the audio ones: a synthetic scene has no load
/// order to read `fBarterMin` and `fBarterMax` out of, and the merchant menu
/// then falls back to the documented vanilla defaults rather than to nothing.
nonisolated protocol BarterDataProviding {
    var barterPricing: BarterPricing { get }
}

/// Optional decoded audio-record stores a provider can expose (M9.2.2).
/// GameViewController pulls these off the provider to construct the world
/// sound director alongside the audio engine. WeatherStore arrives via
/// `WeatherProviding.weatherSystem?.store`.
nonisolated protocol AudioDataProviding {
    var soundStore: SoundRecordStore? { get }
    var aspcStore: AcousticSpaceStore? { get }
    /// Music record index (MUSC/MUST), added in M9.2.3 for the music director.
    var musicStore: MusicRecordStore? { get }
}

/// Adapts `CellSceneBuilder` to the provider seam, pinning the worldspace so
/// the streamer only passes grid coordinates. The builder + its libraries live
/// entirely on the runner's serial queue -- never touched from the main
/// thread -- which is why they need no internal locking.
nonisolated struct BuilderCellSceneProvider: CellSceneProvider, WeatherProviding,
    AudioDataProviding, MovementConfigurationProviding, GlobalDataProviding,
    ScriptDataProviding, ItemDataProviding, BarterDataProviding
{
    let builder: CellSceneBuilder
    let worldspaceEditorID: String
    /// Weather runtime for this worldspace; nil when the plugin has no WTHR.
    var weatherSystem: WeatherSystem?
    /// Sound record index (SOUN/SNDR); nil when the plugin has no sound data.
    var soundStore: SoundRecordStore?
    /// Acoustic-space index (ASPC); nil when the plugin has no ASPC records.
    var aspcStore: AcousticSpaceStore?
    /// Music record index (MUSC/MUST); nil when the plugin has no music data.
    var musicStore: MusicRecordStore?
    /// Global-variable index (GLOB); nil when the plugin has no GLOB records.
    var globalStore: GlobalStore?
    /// Item/container/leveled-list indexes (issue #177); nil when the session
    /// was built without them, which is every synthetic scene.
    var inventoryBaselines: InventoryBaselineResolver?
    /// Equippable-item slot index (issue #178); nil on the same synthetic
    /// scenes, and then equipping reports itself unavailable.
    var equipmentCatalog: EquipmentCatalog?
    /// GMST-derived walk/run values plus explicit documented fallbacks.
    var movementConfiguration: PlayerMovementConfiguration = .synthetic
    /// GMST-derived `fBarterMin` and `fBarterMax` at the milestone's fixed
    /// Speech value (issue #179), defaulting to the documented vanilla numbers.
    var barterPricing: BarterPricing = .vanilla

    /// Compiled-script source for the Papyrus world runtime; nil when the
    /// builder was constructed without a file system (synthetic scenes).
    var scriptFileSystem: VirtualFileSystem? {
        builder.fileSystem
    }

    /// The same master-list resolver every streamed reference key came from.
    var scriptFormIDResolver: FormIDResolver {
        builder.formIDResolver
    }

    func buildCell(at coordinate: CellCoordinate, state: WorldStateSnapshot) throws -> CellScene {
        try builder.buildScene(
            worldspaceEditorID: worldspaceEditorID,
            gridX: coordinate.x,
            gridY: coordinate.y,
            state: state
        )
    }

    func evict(
        droppingMeshKeys meshKeys: Set<String>,
        droppingTextureKeys textureKeys: Set<String>
    ) {
        builder.meshes.evict(dropping: meshKeys)
        builder.collisionModels?.evict(dropping: meshKeys)
        builder.evictCollisionPartitions(dropping: meshKeys)
        builder.textures.evict(dropping: textureKeys)
    }

    func buildDistantLOD(
        center: CellCoordinate,
        hiddenCells: Set<CellCoordinate>
    ) throws -> DistantLODScene? {
        try builder.buildDistantLOD(
            worldspaceEditorID: worldspaceEditorID,
            center: center,
            hiddenCells: hiddenCells
        )
    }

    func buildDoorTransition(
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
nonisolated struct CellBuildResult {
    let coordinate: CellCoordinate
    let result: Result<CellScene, any Error>
    let totalDurationMS: Double

    init(
        coordinate: CellCoordinate,
        result: Result<CellScene, any Error>,
        totalDurationMS: Double = 0
    ) {
        self.coordinate = coordinate
        self.result = result
        self.totalDurationMS = totalDurationMS
    }
}

nonisolated struct CellBuildMetric: Equatable {
    let totalDurationMS: Double
    let collisionDurationMS: Double
    let collisionShapeCount: Int
    let collisionTriangleCount: Int
    /// Actor phase accounting mirrored off CellLoadSummary so the fly bench
    /// can gate latency + exact accounting per cell (5.5).
    var actorDurationMS = 0.0
    var actorDiscoveredCount = 0
    var actorRenderedCount = 0
    var actorDisabledSkipCount = 0
    var actorFailureCount = 0
    /// One reason per counted failure, mirrored off CellLoadSummary so the
    /// fly bench can prove every failure explained (5.6 acceptance).
    var actorFailureReasons: [String] = []
    var actorAnimatedCount = 0
    var actorAnimationFailureCount = 0
    var actorAnimationFailureReasons: [String] = []

    var actorAccountingIsExact: Bool {
        actorDiscoveredCount
            == actorRenderedCount + actorDisabledSkipCount + actorFailureCount
    }

    var actorFailuresAreExplained: Bool {
        actorFailureCount == actorFailureReasons.count
    }

    var actorAnimationAccountingIsExact: Bool {
        actorRenderedCount == actorAnimatedCount + actorAnimationFailureCount
    }

    var actorAnimationFailuresAreExplained: Bool {
        actorAnimationFailureCount == actorAnimationFailureReasons.count
    }
}

nonisolated struct DistantLODBuildResult {
    let center: CellCoordinate
    let result: Result<DistantLODScene?, any Error>
}

nonisolated struct DoorTransitionBuildResult {
    let sourceDoor: FormID
    let result: Result<DoorTransition, any Error>
}

/// Runs cell builds off the main thread and buffers the results for a
/// main-thread poll. The streamer enqueues coordinates and drains completions
/// once per frame; ordering of completions is the executor's business.
nonisolated protocol CellBuildRunning: AnyObject {
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
    func enqueueDistantLOD(center _: CellCoordinate, hiddenCells _: Set<CellCoordinate>) -> Bool {
        false
    }

    func drainCompletedDistantLOD() -> [DistantLODBuildResult] {
        []
    }

    func enqueueDoorTransition(from _: FormID, state _: WorldStateSnapshot) {}
    func drainCompletedDoorTransitions() -> [DoorTransitionBuildResult] {
        []
    }
}

/// Production runner: one serial `DispatchQueue` builds cells one at a time
/// (matching the 3.2 "build one at a time" budget) off the main thread. The
/// provider + its libraries are confined to this queue; the only shared state
/// is the tiny completion buffer, guarded by its own lock. That lock lives
/// here, not inside the libraries -- confinement keeps the caches lock-free.
nonisolated final class SerialCellBuildRunner: CellBuildRunning, @unchecked Sendable {
    private let provider: any CellSceneProvider
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var completed: [CellBuildResult] = []
    /// Execution counts support streaming verification. Kept beside pending
    /// under the same lock so the fly-path gate can prove each desired cell
    /// built once, including completed results not drained yet.
    private var buildCounts: [CellCoordinate: Int] = [:]
    private var buildMetrics: [CellCoordinate: CellBuildMetric] = [:]
    /// Coordinates queued-or-building, so a duplicate enqueue is a no-op --
    /// defence in depth over the streamer's own dedup. Bounds the queue depth
    /// to the grid size regardless of caller bugs (guards the 30 GB runaway).
    private var pending: Set<CellCoordinate> = []
    private var pendingLOD: Set<CellCoordinate> = []
    private var completedLOD: [DistantLODBuildResult] = []
    private var pendingDoorTransitions: Set<FormID> = []
    private var completedDoorTransitions: [DoorTransitionBuildResult] = []

    init(provider: any CellSceneProvider, label: String = "nl.jjgroenendijk.opensky.cellbuild") {
        self.provider = provider
        queue = DispatchQueue(label: label, qos: .utility)
    }

    func enqueue(_ coordinate: CellCoordinate, state: WorldStateSnapshot) {
        lock.lock()
        let isNew = pending.insert(coordinate).inserted
        lock.unlock()
        guard isNew else { return }
        queue.async { [self] in
            lock.lock()
            buildCounts[coordinate, default: 0] += 1
            lock.unlock()
            let started = DispatchTime.now().uptimeNanoseconds
            let result = Result { try provider.buildCell(at: coordinate, state: state) }
            let duration = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            let entry = CellBuildResult(
                coordinate: coordinate,
                result: result,
                totalDurationMS: duration
            )
            lock.lock()
            if case let .success(scene) = result {
                buildMetrics[coordinate] = CellBuildMetric(
                    totalDurationMS: duration,
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
            completed.append(entry)
            lock.unlock()
        }
    }

    func drainCompleted() -> [CellBuildResult] {
        lock.lock()
        defer { lock.unlock() }
        let out = completed
        completed.removeAll(keepingCapacity: true)
        for entry in out {
            pending.remove(entry.coordinate)
        }
        return out
    }

    func enqueueEviction(
        droppingMeshKeys meshKeys: Set<String>,
        droppingTextureKeys textureKeys: Set<String>
    ) {
        guard !meshKeys.isEmpty || !textureKeys.isEmpty else { return }
        queue.async { [self] in
            provider.evict(droppingMeshKeys: meshKeys, droppingTextureKeys: textureKeys)
        }
    }

    @discardableResult
    func enqueueDistantLOD(center: CellCoordinate, hiddenCells: Set<CellCoordinate>) -> Bool {
        lock.lock()
        let isNew = pendingLOD.insert(center).inserted
        lock.unlock()
        guard isNew else { return false }
        queue.async { [self] in
            let result = Result {
                try provider.buildDistantLOD(center: center, hiddenCells: hiddenCells)
            }
            lock.lock()
            completedLOD.append(DistantLODBuildResult(center: center, result: result))
            lock.unlock()
        }
        return true
    }

    func drainCompletedDistantLOD() -> [DistantLODBuildResult] {
        lock.lock()
        defer { lock.unlock() }
        let out = completedLOD
        completedLOD.removeAll(keepingCapacity: true)
        for entry in out {
            pendingLOD.remove(entry.center)
        }
        return out
    }

    func enqueueDoorTransition(from sourceDoor: FormID, state: WorldStateSnapshot) {
        lock.lock()
        let isNew = pendingDoorTransitions.insert(sourceDoor).inserted
        lock.unlock()
        guard isNew else { return }
        queue.async { [self] in
            let result = Result {
                try provider.buildDoorTransition(from: sourceDoor, state: state)
            }
            lock.lock()
            completedDoorTransitions.append(DoorTransitionBuildResult(
                sourceDoor: sourceDoor,
                result: result
            ))
            lock.unlock()
        }
    }

    func drainCompletedDoorTransitions() -> [DoorTransitionBuildResult] {
        lock.lock()
        defer { lock.unlock() }
        let out = completedDoorTransitions
        completedDoorTransitions.removeAll(keepingCapacity: true)
        for entry in out {
            pendingDoorTransitions.remove(entry.sourceDoor)
        }
        return out
    }

    /// Thread-safe snapshot for tests + scripted streaming verification.
    func buildCountsSnapshot() -> [CellCoordinate: Int] {
        lock.lock()
        defer { lock.unlock() }
        return buildCounts
    }

    func buildMetricsSnapshot() -> [CellCoordinate: CellBuildMetric] {
        lock.lock()
        defer { lock.unlock() }
        return buildMetrics
    }
}
