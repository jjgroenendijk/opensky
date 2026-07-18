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
        pending.append(contentsOf: runner.drainCompleted())

        var sceneChanged = false
        if let diff = grid.update(cameraPosition: cameraPosition, loaded: core.accountedCells) {
            let actions = core.apply(diff: diff)
            for coordinate in actions.removals {
                composition.removeCell(at: coordinate)
                sceneChanged = true
            }
            for coordinate in requestsNearestFirst(actions.requests) {
                runner.enqueue(coordinate)
            }
        }

        if integrateOneBuild() {
            sceneChanged = true
        }
        if sceneChanged {
            recomposeAndSink()
        }
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
            switch entry.result {
            case let .success(scene):
                if core.integrate(coordinate: entry.coordinate, kind: .success) == .integrated {
                    composition.setCell(scene, at: entry.coordinate)
                    return true
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

    /// The full grid the manager currently wants around its center.
    var desiredCellCount: Int {
        grid.desiredCells.count
    }

    /// Snapshot of the currently composed multi-cell scene.
    var composedScene: RenderScene {
        composition.composedScene()
    }
}
