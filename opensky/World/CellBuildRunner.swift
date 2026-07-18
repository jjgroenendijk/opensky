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
    func buildCell(at coordinate: CellCoordinate) throws -> CellScene

    /// Drops the given cached assets (a departed cell's keys no resident cell
    /// needs). Runs on the same executor as builds so libraries stay confined.
    func evict(droppingMeshKeys: Set<String>, droppingTextureKeys: Set<String>)
}

/// Adapts `CellSceneBuilder` to the provider seam, pinning the worldspace so
/// the streamer only passes grid coordinates. The builder + its libraries live
/// entirely on the runner's serial queue -- never touched from the main
/// thread -- which is why they need no internal locking.
nonisolated struct BuilderCellSceneProvider: CellSceneProvider {
    let builder: CellSceneBuilder
    let worldspaceEditorID: String

    func buildCell(at coordinate: CellCoordinate) throws -> CellScene {
        try builder.buildScene(
            worldspaceEditorID: worldspaceEditorID,
            gridX: coordinate.x,
            gridY: coordinate.y
        )
    }

    func evict(
        droppingMeshKeys meshKeys: Set<String>,
        droppingTextureKeys textureKeys: Set<String>
    ) {
        builder.meshes.evict(dropping: meshKeys)
        builder.textures.evict(dropping: textureKeys)
    }
}

/// One finished build handed back to the main-thread streamer.
nonisolated struct CellBuildResult {
    let coordinate: CellCoordinate
    let result: Result<CellScene, any Error>
}

/// Runs cell builds off the main thread and buffers the results for a
/// main-thread poll. The streamer enqueues coordinates and drains completions
/// once per frame; ordering of completions is the executor's business.
nonisolated protocol CellBuildRunning: AnyObject {
    func enqueue(_ coordinate: CellCoordinate)
    /// Returns and clears everything finished since the last drain.
    func drainCompleted() -> [CellBuildResult]
    /// Schedules an eviction pass on the build executor (after queued builds),
    /// dropping the given assets a departed cell no longer needs.
    func enqueueEviction(droppingMeshKeys: Set<String>, droppingTextureKeys: Set<String>)
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
    /// Coordinates queued-or-building, so a duplicate enqueue is a no-op --
    /// defence in depth over the streamer's own dedup. Bounds the queue depth
    /// to the grid size regardless of caller bugs (guards the 30 GB runaway).
    private var pending: Set<CellCoordinate> = []

    init(provider: any CellSceneProvider, label: String = "nl.jjgroenendijk.opensky.cellbuild") {
        self.provider = provider
        queue = DispatchQueue(label: label, qos: .utility)
    }

    func enqueue(_ coordinate: CellCoordinate) {
        lock.lock()
        let isNew = pending.insert(coordinate).inserted
        lock.unlock()
        guard isNew else { return }
        queue.async { [self] in
            lock.lock()
            buildCounts[coordinate, default: 0] += 1
            lock.unlock()
            let result = Result { try provider.buildCell(at: coordinate) }
            let entry = CellBuildResult(coordinate: coordinate, result: result)
            lock.lock()
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

    /// Thread-safe snapshot for tests + scripted streaming verification.
    func buildCountsSnapshot() -> [CellCoordinate: Int] {
        lock.lock()
        defer { lock.unlock() }
        return buildCounts
    }
}
