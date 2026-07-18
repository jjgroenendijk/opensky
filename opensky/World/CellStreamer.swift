// Live cell streaming controller (todo 3.2 async build): the main-thread face
// of streaming. Owns the grid manager, the resident-cell composition, the
// bookkeeping core, and a build runner. Driven once per frame with the camera
// position: diffs the grid, dispatches missing cells to the off-main runner,
// integrates finished builds under a per-frame budget, and hands the recomposed
// scene to a sink (Renderer.setScene in the app). Concurrency + void-cell
// design: docs/engine/cell-streaming.md.

import OSLog
import simd

final class CellStreamer {
    /// Receives the recomposed scene whenever it changes (integration or
    /// unload). `camera` is non-nil only on the first integrated cell -- the
    /// framing reseed that snaps the view onto the launch cell once it
    /// arrives; later changes pass nil so they never yank the free-fly view.
    typealias SceneSink = (RenderScene, SceneCamera?) -> Void

    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "CellStream"
    )

    private var grid: CellGridManager
    private var composition = CellSceneComposition()
    private var core = CellStreamCore()
    private let runner: any CellBuildRunning
    private let sink: SceneSink

    /// Desired requests not yet submitted. Only one build reaches the runner
    /// at a time, so recentering can discard obsolete backlog before it does
    /// I/O and eviction always queues ahead of the next build.
    private var requests: [CellCoordinate] = []
    private var activeBuild: CellCoordinate?

    /// Finished builds drained from the runner, awaiting integration. Bounded
    /// by the grid size: at most one entry per in-flight cell.
    private var pending: [CellBuildResult] = []
    /// Set once the first drawable cell frames the camera; every later
    /// recompose passes a nil camera so the free-fly view is left alone.
    private var hasSeededCamera = false

    /// - Parameters:
    ///   - center: grid center at launch (streaming starts on FirstRenderCell).
    ///   - radius: rings around center (default 2 -> 5x5).
    ///   - runner: off-main build executor (serial queue in the app, a fake in
    ///     tests).
    ///   - sink: recomposed-scene handoff (Renderer.setScene in the app).
    init(
        center: CellCoordinate,
        radius: Int32 = CellGridManager.defaultRadius,
        runner: any CellBuildRunning,
        sink: @escaping SceneSink
    ) {
        grid = CellGridManager(
            initialPosition: CellGridManager.cellCenter(of: center),
            radius: radius
        )
        self.runner = runner
        self.sink = sink
    }

    /// One frame's drive. Collects finished builds, re-grids around the
    /// camera (dispatching newly-needed cells, dropping cells that left the
    /// grid), integrates at most one drawable build (a swap is a full
    /// recompose), and sinks the recomposed scene when anything changed.
    func update(cameraPosition: SIMD3<Float>) {
        let completed = runner.drainCompleted()
        if !completed.isEmpty {
            pending.append(contentsOf: completed)
            activeBuild = nil
        }

        var sceneChanged = false
        // Renderer starts on its demo pose. Keep the configured launch grid
        // fixed until the first drawable cell supplies the framing camera.
        let effectivePosition = hasSeededCamera
            ? cameraPosition
            : CellGridManager.cellCenter(of: grid.center)
        if let diff = grid.update(cameraPosition: effectivePosition, loaded: core.accountedCells) {
            let actions = core.apply(diff: diff)
            requests.removeAll { !core.inFlight.contains($0) }
            if !actions.removals.isEmpty {
                unload(actions.removals)
                sceneChanged = true
            }
            requests.append(contentsOf: requestsNearestFirst(actions.requests))
        }

        if integrateOneBuild() {
            sceneChanged = true
        }
        if sceneChanged {
            recomposeAndSink()
        }
        dispatchNextBuild()
    }

    /// Drops unloaded cells from the composition and schedules eviction of the
    /// assets they used that no remaining resident cell needs. Drop-set (the
    /// departed cells' keys minus the resident union) so in-flight builds for
    /// the new grid keep their freshly-loaded assets (docs/engine/cell-streaming.md
    /// eviction). Eviction runs on the build queue -- confinement holds.
    private func unload(_ coordinates: [CellCoordinate]) {
        var departed = CellAssets()
        for coordinate in coordinates {
            guard let removed = composition.removeCell(at: coordinate) else { continue }
            departed.meshKeys.formUnion(removed.assets.meshKeys)
            departed.textureKeys.formUnion(removed.assets.textureKeys)
        }
        evictUnused(departed)
    }

    /// Schedules only keys no resident cell owns. With one submitted build,
    /// this eviction enters the serial runner before the next build starts.
    private func evictUnused(_ candidates: CellAssets) {
        let resident = composition.residentAssets()
        runner.enqueueEviction(
            droppingMeshKeys: candidates.meshKeys.subtracting(resident.meshKeys),
            droppingTextureKeys: candidates.textureKeys.subtracting(resident.textureKeys)
        )
    }

    private func dispatchNextBuild() {
        guard activeBuild == nil, pending.isEmpty, !requests.isEmpty else { return }
        let coordinate = requests.removeFirst()
        activeBuild = coordinate
        runner.enqueue(coordinate)
    }

    // MARK: - Integration

    /// Drains completed builds, folding each into the core. Void / failed /
    /// stale outcomes are cheap (no recompose) and drained freely; the first
    /// drawable success becomes resident and stops the drain -- that is the
    /// per-frame budget of one recompose. Returns whether a cell was
    /// integrated (composition changed). Remaining successes wait for the
    /// next frame.
    private func integrateOneBuild() -> Bool {
        while !pending.isEmpty {
            let entry = pending.removeFirst()
            requests.removeAll { $0 == entry.coordinate }
            switch entry.result {
            case let .success(scene):
                let decision = core.integrate(coordinate: entry.coordinate, kind: .success)
                if decision == .integrated {
                    composition.setCell(scene, at: entry.coordinate)
                    return true
                }
                if decision == .discardedStale {
                    evictUnused(scene.assets)
                }
            // Stale success (unloaded mid-flight) -- drop, keep draining.
            case let .failure(error):
                let kind: CellStreamCore.BuildKind = Self.isVoid(error) ? .void : .failure
                let decision = core.integrate(coordinate: entry.coordinate, kind: kind)
                log(coordinate: entry.coordinate, decision: decision, error: error)
            }
        }
        return false
    }

    /// A void slot (no CELL at the grid position) throws `cellNotFound`;
    /// everything else is a genuine build failure.
    private static func isVoid(_ error: any Error) -> Bool {
        guard let cellError = error as? CellSceneError else { return false }
        if case .cellNotFound = cellError {
            return true
        }
        return false
    }

    private func log(
        coordinate: CellCoordinate,
        decision: CellStreamCore.IntegrationResult,
        error: any Error
    ) {
        let position = "(\(coordinate.x),\(coordinate.y))"
        switch decision {
        case .recordedVoid:
            Self.logger.debug("[INFO] cell \(position, privacy: .public) void, not retried")
        case .recordedFailed:
            let reason = String(describing: error)
            Self.logger.warning(
                """
                [WARNING] cell \(position, privacy: .public) build failed, \
                not retried: \(reason, privacy: .public)
                """
            )
        case .discardedStale, .integrated:
            break
        }
    }

    /// Recomposes the resident cells and hands the scene to the sink. The
    /// first recompose that has drawable bounds frames the camera; all later
    /// ones pass nil.
    private func recomposeAndSink() {
        let scene = composition.composedScene()
        var camera: SceneCamera?
        if !hasSeededCamera, let bounds = composition.composedBounds() {
            camera = SceneCamera.framing(bounds: bounds)
            hasSeededCamera = true
        }
        sink(scene, camera)
        logFootprint()
    }

    /// One-line memory report per recompose -- the streaming footprint budget
    /// is measured, not guessed (docs/engine/cell-streaming.md memory budget).
    private func logFootprint() {
        guard let megabytes = MemoryFootprint.physFootprintMB() else { return }
        let residentCount = residentCellCount
        let voidCount = voidCellCount
        let inFlightCount = inFlightCellCount
        Self.logger.info(
            """
            [INFO] stream: \(residentCount, privacy: .public) resident, \
            \(voidCount, privacy: .public) void, \
            \(inFlightCount, privacy: .public) in flight, \
            footprint \(Int(megabytes), privacy: .public) MB
            """
        )
    }

    /// Dispatches center-out so the launch cell (and nearest neighbors) build
    /// first -- the first integrated cell is the one that frames the camera.
    /// Deterministic tie-break by coordinate keeps dispatch order stable.
    private func requestsNearestFirst(_ requests: [CellCoordinate]) -> [CellCoordinate] {
        let center = grid.center
        return requests.sorted { lhs, rhs in
            let lhsDistance = Self.squaredDistance(lhs, center)
            let rhsDistance = Self.squaredDistance(rhs, center)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            return (lhs.x, lhs.y) < (rhs.x, rhs.y)
        }
    }

    private static func squaredDistance(_ lhs: CellCoordinate, _ rhs: CellCoordinate) -> Int {
        let deltaX = Int(lhs.x) - Int(rhs.x)
        let deltaY = Int(lhs.y) - Int(rhs.y)
        return deltaX * deltaX + deltaY * deltaY
    }

    // MARK: - Inspection (streaming verification + tests)

    /// Grid slots that reached a terminal state: resident + void + failed.
    var resolvedCellCount: Int {
        core.resident.count + core.void.count + core.failed.count
    }

    var residentCellCount: Int {
        core.resident.count
    }

    var residentCoordinates: Set<CellCoordinate> {
        core.resident
    }

    var voidCellCount: Int {
        core.void.count
    }

    var failedCellCount: Int {
        core.failed.count
    }

    var inFlightCellCount: Int {
        core.inFlight.count
    }

    var pendingCompletionCount: Int {
        pending.count
    }

    var queuedRequestCount: Int {
        requests.count
    }

    /// The full grid the manager currently wants around its center.
    var desiredCellCount: Int {
        grid.desiredCells.count
    }

    /// Snapshot of the currently composed multi-cell scene.
    var composedScene: RenderScene {
        composition.composedScene()
    }
}
