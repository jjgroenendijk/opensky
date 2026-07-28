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

    static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "CellStream"
    )

    var grid: CellGridManager
    var composition = CellSceneComposition()
    var core = CellStreamCore()
    let runner: any CellBuildRunning
    let sink: SceneSink
    /// Live XCLR region feed (M7.2.3): fires with the current exterior center
    /// cell's REGN FormIDs whenever they change, so region-weighted weather
    /// selection runs live. GameViewController wires it to
    /// `Renderer.weather.setRegions`. nil in tests that ignore weather.
    var onCenterRegionsChanged: (([FormID]) -> Void)?
    /// Last region set pushed through `onCenterRegionsChanged`; nil = never
    /// emitted. Guards against re-firing an unchanged set every frame.
    private var lastEmittedRegions: [FormID]?
    /// World SFX director subscription (M9.2.2): fires with the current cell's
    /// ambience identity whenever it changes (exterior recenter, interior
    /// enter/exit). The director resolves the bed and starts/stops loops.
    var onAmbienceContextChanged: ((AmbienceContext) -> Void)?
    /// Last ambience key pushed; nil = never emitted. Guards against re-firing.
    /// Internal for the CellStreamerAmbience satellite to read/write.
    var lastEmittedAmbienceKey: AmbienceKey?
    /// Music director subscription (M9.2.3): fires with the current cell's
    /// music-selection identity whenever it changes. The director resolves the
    /// playlist and crossfades.
    var onMusicContextChanged: ((MusicContext) -> Void)?
    /// Last music key pushed; nil = never emitted. Internal for the
    /// CellStreamerMusic satellite to read/write.
    var lastEmittedMusicKey: MusicKey?
    /// Retained for deterministic walk benchmarks that inspect nearby doors.
    /// Production use-key activation is view-ray based.
    static let doorActivationRadius = InteractionRay.defaultMaximumDistance

    /// Supplies the runtime world state each dispatched build runs against
    /// (issue #160). Called on the main thread at dispatch time, so the build
    /// sees the store exactly as it was when the work left the main thread.
    /// The default keeps every build on the plugin baseline, which is what
    /// tests and any caller with no store want.
    var stateSource: () -> WorldStateSnapshot = { .empty }

    /// Desired requests not yet submitted. Only one build reaches the runner
    /// at a time, so recentering can discard obsolete backlog before it does
    /// I/O and eviction always queues ahead of the next build.
    private var requests: [CellCoordinate] = []
    /// Resident cells awaiting a world-state rebuild, oldest request first.
    /// Kept apart from `requests` so first loads keep their center-out
    /// priority; rebuilds are dispatched only once the load queue is drained.
    /// Details in the CellStreamerRuntimeState satellite.
    var rebuildRequests: [CellCoordinate] = []
    /// Highest journal sequence of a mutation attributed to each cell. A
    /// resident scene is current exactly while its `stateSequence` is at
    /// least this value.
    var cellMutationSequence: [CellCoordinate: UInt64] = [:]
    /// Same, for the interior scene currently owning the view.
    var interiorMutationSequence: UInt64 = 0
    /// Source door of the transition that produced the current interior, so a
    /// mutation inside it can be rebuilt through the door-transition path.
    var interiorSourceDoor: FormID?
    /// True while the in-flight door transition is an interior rebuild rather
    /// than a player-driven move, which suppresses the camera teleport.
    var interiorRebuildInFlight = false
    private var activeBuild: CellCoordinate?

    /// Finished builds drained from the runner, awaiting integration. Bounded
    /// by the grid size: at most one entry per in-flight cell.
    private var pending: [CellBuildResult] = []
    /// Set once the first drawable cell frames the camera; every later
    /// recompose passes a nil camera so the free-fly view is left alone.
    private var hasSeededCamera = false
    /// Internal (not private) so the CellStreamerCoverage satellite can read
    /// and write it; the coverage state below is shared for the same reason.
    var requestedLODCenter: CellCoordinate?
    /// Once settled coverage exists, recenter builds stay offscreen here.
    /// Old full cells + LOD remain composed until replacement LOD arrives,
    /// then full grid + ring swap in one recompose.
    var coverageTransitionActive = false
    var stagedCells: [CellCoordinate: CellScene] = [:]
    var interiorScene: CellScene?
    var transitionInFlight: FormID?
    private(set) var doorTransitionFailureCount = 0
    var interactionTarget: InteractionTarget?
    /// Fires when view-ray target identity, text, or hit details change.
    var onInteractionTargetChanged: ((InteractionTarget?) -> Void)?
    /// Engine-owned use-key event. HUD observes targets; Papyrus subscribes
    /// here later without taking ownership of raycast or door behavior.
    var onInteraction: ((InteractionEvent) -> Void)?
    /// Player-driven door motion boundaries. World audio consumes these to
    /// start the authored movement loop, retire it, and play the close sound.
    var onInteractionAnimation: ((InteractionAnimationEvent) -> Void)?
    /// Source placement retained across an asynchronous door build. Runtime
    /// state rebuilds have no player interaction and leave this nil.
    var doorMotionInteraction: PlacedInteraction?

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

    func noteDoorTransitionFailure() {
        doorTransitionFailureCount += 1
    }

    /// One frame's drive. Collects finished builds, re-grids around the
    /// camera (dispatching newly-needed cells, dropping cells that left the
    /// grid), integrates at most one drawable build (a swap is a full
    /// recompose), and sinks the recomposed scene when anything changed.
    func update(
        cameraPosition: SIMD3<Float>,
        interactionRay: InteractionRay? = nil,
        activate: Bool = false
    ) {
        let completed = runner.drainCompleted()
        if !completed.isEmpty {
            pending.append(contentsOf: completed)
            activeBuild = nil
        }
        let completedLOD = runner.drainCompletedDistantLOD()
        if finishDoorTransition(runner.drainCompletedDoorTransitions()) {
            return
        }
        let isInside = updateInteriorIfNeeded(
            completedLOD: completedLOD
        )
        if isInside {
            updateInteractionTarget(ray: interactionRay)
            if activate {
                activateInteractionTarget()
            }
            return
        }

        var sceneChanged = false
        // Renderer starts on its demo pose. Keep the configured launch grid
        // fixed until the first drawable cell supplies the framing camera.
        let effectivePosition = hasSeededCamera
            ? cameraPosition
            : CellGridManager.cellCenter(of: grid.center)
        let previousCenter = grid.center
        if let diff = grid.update(cameraPosition: effectivePosition, loaded: core.accountedCells) {
            if grid.center != previousCenter, composition.distantLOD != nil {
                coverageTransitionActive = true
            }
            let actions = core.apply(diff: diff)
            requests.removeAll { !core.inFlight.contains($0) }
            pruneRebuildState()
            discardStagedCells(outside: grid.desiredCells)
            if !actions.removals.isEmpty, !coverageTransitionActive {
                unload(actions.removals)
                sceneChanged = true
            }
            requests.append(contentsOf: requestsNearestFirst(actions.requests))
        }

        if integrateOneBuild() {
            sceneChanged = true
        }
        if integrateDistantLOD(completedLOD) {
            sceneChanged = true
        }
        if sceneChanged {
            recomposeAndSink()
        }
        updateInteractionTarget(ray: interactionRay)
        if activate {
            activateInteractionTarget()
        }
        dispatchNextBuild()
        requestDistantLODIfNeeded()
        emitCenterRegionsIfChanged()
        emitAmbienceContextIfNeeded()
        emitMusicContextIfNeeded()
    }

    /// Pushes the current exterior center cell's XCLR regions to the weather
    /// feed when they change. Only fires for a resident exterior center: the
    /// interior path returns before this (regions left unchanged — weather is
    /// exterior-only, so entering a building keeps the exterior region so the
    /// exit resumes seamlessly), and a center that has not streamed in yet is
    /// skipped so a brief loading gap never drops region weighting.
    private func emitCenterRegionsIfChanged() {
        guard let scene = composition.cells[grid.center] else { return }
        let regions = scene.regions
        guard regions != lastEmittedRegions else { return }
        lastEmittedRegions = regions
        onCenterRegionsChanged?(regions)
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
    func evictUnused(_ candidates: CellAssets) {
        var resident = composition.residentAssets()
        if let interiorScene {
            resident.meshKeys.formUnion(interiorScene.assets.meshKeys)
            resident.textureKeys.formUnion(interiorScene.assets.textureKeys)
        }
        for scene in stagedCells.values {
            resident.meshKeys.formUnion(scene.assets.meshKeys)
            resident.textureKeys.formUnion(scene.assets.textureKeys)
        }
        runner.enqueueEviction(
            droppingMeshKeys: candidates.meshKeys.subtracting(resident.meshKeys),
            droppingTextureKeys: candidates.textureKeys.subtracting(resident.textureKeys)
        )
    }

    /// Submits at most one build per frame. First loads drain before world-
    /// state rebuilds, so a cell that has never been drawn still arrives
    /// center-out; a rebuild only ever displaces an already-drawn cell, so
    /// deferring it costs nothing visible. The world-state snapshot is taken
    /// here, at dispatch, which is the last main-thread moment before the
    /// build leaves for the serial runner (issue #160).
    private func dispatchNextBuild() {
        guard
            transitionInFlight == nil,
            interiorScene == nil,
            activeBuild == nil,
            pending.isEmpty
        else { return }
        if !requests.isEmpty {
            let coordinate = requests.removeFirst()
            activeBuild = coordinate
            runner.enqueue(coordinate, state: stateSource())
            return
        }
        dispatchNextRebuild()
    }

    /// Takes the first rebuild request the core still accepts. A request whose
    /// cell stopped being resident (unloaded, or its first build has not
    /// landed yet) is dropped here rather than dispatched; for the unloaded
    /// case that is the cancellation, and for the not-yet-resident case the
    /// integration of the first build re-queues it against the fresher state.
    private func dispatchNextRebuild() {
        while !rebuildRequests.isEmpty {
            let coordinate = rebuildRequests.removeFirst()
            guard core.beginRebuild(coordinate) else { continue }
            activeBuild = coordinate
            runner.enqueue(coordinate, state: stateSource())
            return
        }
    }

    // MARK: - Integration

    /// Drains completed builds, folding each into the core. Void / failed /
    /// stale outcomes are cheap (no recompose) and drained freely; the first
    /// drawable success becomes resident and stops the drain -- that is the
    /// per-frame budget of one recompose. Returns whether a cell was
    /// integrated (composition changed). Remaining successes wait for the
    /// next frame.
    func integrateOneBuild() -> Bool {
        while !pending.isEmpty {
            let entry = pending.removeFirst()
            requests.removeAll { $0 == entry.coordinate }
            switch entry.result {
            case let .success(scene):
                let decision = core.integrate(coordinate: entry.coordinate, kind: .success)
                if decision == .integrated {
                    requeueRebuildIfStateMoved(entry.coordinate, scene: scene)
                    if coverageTransitionActive {
                        if let replaced = stagedCells.updateValue(scene, forKey: entry.coordinate) {
                            evictUnused(replaced.assets)
                        }
                        return false
                    }
                    if let replaced = composition.setCell(scene, at: entry.coordinate) {
                        evictUnused(replaced.assets)
                    }
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
}

extension CellStreamer {
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

    /// Requests a fresh ring for current center. If a build is already in
    /// flight, requestDistantLODIfNeeded retries until runner accepts it.
    func invalidateDistantLOD() {
        requestedLODCenter = nil
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

    var distantLODBlockCount: Int {
        composition.distantLOD?.blockCount ?? 0
    }

    var composedCellCount: Int {
        composition.cellCount
    }

    var isCoverageTransitionActive: Bool {
        coverageTransitionActive
    }

    var isInterior: Bool {
        interiorScene != nil
    }

    var residentCollisionStats: StaticCollisionStats {
        if let interiorScene {
            return interiorScene.staticCollision.stats
        }
        return composition.collisionStats()
    }
}
