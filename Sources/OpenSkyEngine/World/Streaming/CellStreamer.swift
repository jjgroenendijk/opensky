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
    /// I/O and eviction always queues ahead of the next build. Readable (not
    /// writable) cross-file for the inspection satellite.
    private(set) var requests: [CellCoordinate] = []
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
    /// by the grid size: at most one entry per in-flight cell. Readable (not
    /// writable) cross-file for the inspection satellite.
    private(set) var pending: [CellBuildResult] = []
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
    /// Engine-owned use-key event, multicast since issue #172: world audio and
    /// the Papyrus activation bridge both subscribe, in registration order,
    /// and neither takes ownership of the raycast or of door behavior.
    let onInteraction = CallbackFanOut<InteractionEvent>()
    /// Everything Talk activation needs from the streamer (issue #205), in one
    /// value so the three parts of one seam stay together.
    var talk = TalkTargetingSeam()
    /// Player-driven door motion boundaries. World audio consumes these to
    /// start the authored movement loop, retire it, and play the close sound.
    var onInteractionAnimation: ((InteractionAnimationEvent) -> Void)?
    /// Source placement retained across an asynchronous door build. Runtime
    /// state rebuilds have no player interaction and leave this nil.
    var doorMotionInteraction: PlacedInteraction?
    /// A cell became part of the live world (issue #171). The flag is true for
    /// a first integration and false for a re-integration of a cell that never
    /// left — a world-state rebuild or an interior refresh — so a subscriber
    /// can attach scripts once without re-firing load events. A cell built
    /// offscreen during a coverage transition fires only when it is committed.
    /// Emission lives in the CellStreamerPapyrus satellite.
    var onCellAttached: ((CellScene, Bool) -> Void)?
    /// A cell left the live world: unloaded off the grid, dropped by a
    /// coverage transition, or replaced by a door transition.
    var onCellDetached: ((CellSceneLocation) -> Void)?
    /// The player entered or left an authored trigger volume (issue #173).
    /// Multicast because the Papyrus bridge and a later occupancy readout are
    /// both plausible subscribers. Emission lives in the CellStreamerTriggers
    /// satellite.
    let onTriggerTransition = CallbackFanOut<TriggerTransitionEvent>()
    /// Trigger volumes the player capsule was inside as of the last walk-mode
    /// frame, keyed by the authoring REFR. The per-frame diff against this set
    /// is what makes enter and leave edge events.
    var occupiedTriggers: Set<ReferenceKey> = []
    /// Feet position of the previous walk-mode trigger test, so a frame that
    /// moved further than a capsule radius can be swept rather than sampled
    /// only at its destination. Nil outside walk mode.
    var lastTriggerFeetPosition: SIMD3<Float>?
    /// Recent trigger edges for the `World > World > Triggers` readout
    /// (issue #173). Filled by an ordinary `onTriggerTransition` subscriber
    /// registered in `init`, so the dispatch path stays unaware of it.
    let triggerLog = TriggerEventLog()
    /// Simulated rigid bodies of the resident world (issue #193). Reconciled
    /// against residency once per frame by the CellStreamerPhysics satellite.
    var dynamicBodies = DynamicBodyWorld()
    /// A body came to rest and its transform should be persisted under the
    /// reference's `.transform` component. The store is not reachable from
    /// here, so the app wires this to `WorldStateStore.set`.
    var onBodySettled: ((
        ReferenceKey, ReferenceTransformOverride, CellSceneLocation
    ) -> Void)?
    /// Where the simulated bodies have moved since their cells were built,
    /// published once per physics tick so the draw that follows places them
    /// live (issue #193). The renderer is not reachable from here either, so
    /// the app wires this to `Renderer.dynamicInstanceDeltas`.
    var onDynamicPosesChanged: (([UInt32: float4x4]) -> Void)?
    /// Resident graph, repath backlog and completion sink (issue #200).
    var navigationState = CellStreamerNavigationState()
    /// Active NPC capsules, their drive, and app callbacks (issue #423).
    var npcMovementState = CellStreamerNPCMovementState()

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
        installTriggerLogging()
    }

    /// One frame's drive. Collects finished builds, re-grids around the
    /// camera (dispatching newly-needed cells, dropping cells that left the
    /// grid), integrates at most one drawable build (a swap is a full
    /// recompose), and sinks the recomposed scene when anything changed.
    /// - Parameter playerCapsule: authoritative walk-mode capsule pose for
    ///   this frame, or nil when the player is not walking. Trigger-volume
    ///   occupancy is tested here, once per rendered frame, and never in the
    ///   120 Hz substep loop (issue #173).
    func update(
        cameraPosition: SIMD3<Float>,
        interactionRay: InteractionRay? = nil,
        activate: Bool = false,
        playerCapsule: PlayerCapsuleState? = nil,
        frameTime: Float = 0
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
            // Interiors carry most authored trigger volumes, so the test runs
            // on this path too rather than only on the exterior tail below.
            updateTriggerOccupancy(playerCapsule)
            advanceWorldSystems(frameTime: frameTime, player: playerCapsule)
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
        updateTriggerOccupancy(playerCapsule)
        advanceWorldSystems(frameTime: frameTime, player: playerCapsule)
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

    /// Schedules only keys no resident cell owns. With one submitted build,
    /// this eviction enters the serial runner before the next build starts.
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
                // A world-state rebuild re-integrates a cell that never left,
                // so it must not read as a fresh attach (issue #171). The core
                // clears `rebuilding` inside `integrate`, hence the read here.
                let isRebuild = core.rebuilding.contains(entry.coordinate)
                let decision = core.integrate(coordinate: entry.coordinate, kind: .success)
                if decision == .integrated {
                    requeueRebuildIfStateMoved(entry.coordinate, scene: scene)
                    if coverageTransitionActive {
                        if let replaced = stagedCells.updateValue(scene, forKey: entry.coordinate) {
                            evictUnused(replaced.assets)
                        }
                        // Staged offscreen: announced when the transition commits.
                        return false
                    }
                    if let replaced = composition.setCell(scene, at: entry.coordinate) {
                        evictUnused(replaced.assets)
                    }
                    emitCellAttached(scene, firstIntegration: !isRebuild)
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
    func noteDoorTransitionFailure() {
        doorTransitionFailureCount += 1
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

    /// Requests a fresh ring for current center. If a build is already in
    /// flight, requestDistantLODIfNeeded retries until runner accepts it.
    func invalidateDistantLOD() {
        requestedLODCenter = nil
    }
}
