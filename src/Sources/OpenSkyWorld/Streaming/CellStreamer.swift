// The main-thread face of cell streaming. Each frame it diffs the grid around
// the camera, sends missing cells to the off-main runner, integrates finished
// builds under a budget, and hands the scene to a sink
// (docs/engine/cell-streaming.md).

import Foundation
import OpenSkyAudio
public import OpenSkyCells
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyPhysics
public import OpenSkyPlayer
public import OpenSkyRenderCore
public import OpenSkyRendering
public import OpenSkyTerrain
public import OpenSkyWorldInterface
public import OpenSkyWorldState
public import simd

public typealias SettledBodyHandler = (
    ReferenceKey, ReferenceTransformOverride, CellSceneLocation
) -> Void

public final class CellStreamer {
    public let doorState = CellStreamerDoorState()
    public let events = CellStreamerEvents()
    /// Receives the recomposed scene whenever it changes (integration or
    /// unload). `camera` is non-nil only on the first integrated cell -- the
    /// framing reseed that snaps the view onto the launch cell once it
    /// arrives; later changes pass nil so they never yank the free-fly view.
    public typealias SceneSink = (RenderScene, SceneCamera?) -> Void

    public static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky", category: "CellStream"
    )

    public var grid: CellGridManager
    /// The worldspace the exterior cells come from. A door or a teleport changes it.
    public private(set) var worldspaceEditorID: String
    public var composition = CellSceneComposition() {
        didSet { actorPoseRevision &+= 1 }
    }

    /// Rises on every change that can move an actor or change which actors are
    /// resident: the composition, the interior scene, and the NPC movement state.
    public private(set) var actorPoseRevision: UInt64 = 0
    public var core = CellStreamCore()
    public let runner: any CellBuildRunning

    /// The asset cache sizes, when the runner keeps a cache.
    public var cachedAssetCounts: CachedAssetCounts? {
        (runner as? SerialCellBuildRunner)?.cachedAssetCounts
    }

    public let sink: SceneSink
    /// Retained for deterministic walk benchmarks that inspect nearby doors.
    /// Production use-key activation is view-ray based.
    public static let doorActivationRadius = InteractionRay.defaultMaximumDistance

    /// The world state each build runs against, read on the main thread at dispatch. The
    /// default is the plugin baseline.
    public var stateSource: () -> WorldStateSnapshot = { .empty }
    /// Plugin records for references no resident cell holds.
    public var placedRecords: PlacedRecordLookup?

    /// Desired requests not yet submitted. Only one build reaches the runner
    /// at a time, so recentering can discard obsolete backlog before it does
    /// I/O and eviction always queues ahead of the next build. Readable (not
    /// writable) cross-file for the inspection satellite.
    public internal(set) var requests: [CellCoordinate] = []
    /// Resident cells awaiting a world-state rebuild, oldest request first.
    /// Kept apart from `requests` so first loads keep their center-out
    /// priority; rebuilds are dispatched only once the load queue is drained.
    /// Details in the CellStreamerRuntimeState satellite.
    public var rebuildRequests: [CellCoordinate] = []
    /// Highest journal sequence of a mutation attributed to each cell. A
    /// resident scene is current exactly while its `stateSequence` is at
    /// least this value.
    public var cellMutationSequence: [CellCoordinate: UInt64] = [:]
    /// Same, for the interior scene currently owning the view.
    public var interiorMutationSequence: UInt64 = 0
    /// True while the in-flight door transition is an interior rebuild rather
    /// than a player-driven move, which suppresses the camera teleport.
    public var interiorRebuildInFlight = false
    var activeBuild: CellCoordinate?

    /// Finished builds drained from the runner, awaiting integration. Bounded
    /// by the grid size: at most one entry per in-flight cell. Readable (not
    /// writable) cross-file for the inspection satellite.
    public internal(set) var pending: [CellBuildResult] = []
    /// Set once the first drawable cell frames the camera, or a move places it;
    /// every later recompose passes a nil camera so the free-fly view is left alone.
    var hasSeededCamera = false
    /// While held, nothing loads: the main menu shows before the player picks a start.
    public var isHeld = false
    /// Internal (not private) so the CellStreamerCoverage satellite can read
    /// and write it; the coverage state below is shared for the same reason.
    public var requestedLODCenter: CellCoordinate?
    /// The center whose distant ring was last integrated or failed.
    public internal(set) var settledLODCenter: CellCoordinate?
    /// The center whose quick first ring was rebuilt once to add its large references.
    var largeReferenceRequestCenter: CellCoordinate?
    /// The center whose large-reference rebuild was integrated or failed.
    var largeReferenceSettledCenter: CellCoordinate?
    /// Once settled coverage exists, recenter builds stay offscreen here.
    /// Old full cells + LOD remain composed until replacement LOD arrives,
    /// then full grid + ring swap in one recompose.
    public var coverageTransitionActive = false
    public var stagedCells: [CellCoordinate: CellScene] = [:]
    public var interiorScene: CellScene? {
        didSet {
            actorPoseRevision &+= 1
            interiorActorPlacements = interiorScene.map {
                ResidentActorPlacement.index([(location: $0.location, references: $0.references)])
            }
        }
    }

    /// Nil outside an interior, where `composition` answers instead.
    private(set) var interiorActorPlacements: [ReferenceKey: ResidentActorPlacement]?
    public var transitionInFlight: FormID?
    public var interactionTarget: InteractionTarget?
    /// Everything Talk activation needs from the streamer.
    public var talk = TalkTargetingSeam()
    /// The lock check in front of every use-key activation.
    public var activationGate = ActivationGateSeam()
    /// Each sequence door's leaf moves from rest, by reference; its collision follows.
    public var sequenceDoorLeaves: [UInt32: [float4x4]] = [:]
    /// Simulated rigid bodies, reconciled against residency each frame.
    public var dynamicBodies = DynamicBodyWorld()
    /// True while a settled body's transform is written. The body already draws
    /// at that pose, so the write rebuilds no cell; a later build bakes it in.
    public var isRecordingSettledBody = false
    /// Resident graph, repath backlog and completion sink.
    public var navigationState = CellStreamerNavigationState()
    /// Active NPC capsules, their drive, and app callbacks.
    public var npcMovementState = CellStreamerNPCMovementState() {
        didSet { actorPoseRevision &+= 1 }
    }

    /// - Parameters:
    ///   - center: grid center at launch (streaming starts on FirstRenderCell).
    ///   - worldspace: the worldspace the runner's provider starts in.
    ///   - radius: rings around center (default 2 -> 5x5).
    ///   - runner: off-main build executor (a serial queue, or a test fake).
    ///   - sink: recomposed-scene handoff (Renderer.setScene in the app).
    public init(
        center: CellCoordinate,
        worldspace: String = FirstRenderCell.worldspaceEditorID,
        radius: Int32 = CellGridManager.defaultRadius,
        runner: any CellBuildRunning,
        sink: @escaping SceneSink
    ) {
        worldspaceEditorID = worldspace
        grid = CellGridManager(
            initialPosition: CellGridManager.cellCenter(of: center),
            radius: radius
        )
        self.runner = runner
        self.sink = sink
        triggers.registerTriggerLog()
    }

    /// One frame: collects finished builds, re-grids around the camera,
    /// integrates at most one drawable build, and sinks the scene on a change.
    /// Trigger occupancy is tested here once per frame, never in the 120 Hz
    /// substep loop. `playerCapsule` is nil when the player is not walking.
    public func update(
        cameraPosition: SIMD3<Float>,
        interactionRay: InteractionRay? = nil,
        activate: Bool = false,
        playerCapsule: PlayerCapsuleState? = nil,
        frameTime: Float = 0
    ) {
        guard !isHeld else { return }
        let completed = runner.drainCompleted()
        if !completed.isEmpty {
            pending.append(contentsOf: completed.filter(builds.builtHere))
            activeBuild = nil
        }
        let completedLOD = runner.drainCompletedDistantLOD().filter(builds.builtHere)
        let transition = transitions.drainDoorTransitions(frameTime: frameTime)
        if transitions.finishDoorTransition(transition) {
            return
        }
        let isInside = transitions.updateInteriorIfNeeded(completedLOD: completedLOD)
        if isInside {
            residents.updateInteractionTarget(ray: interactionRay)
            if activate {
                residents.activateInteractionTarget()
            }
            // Interiors carry most authored trigger volumes, so the test runs
            // on this path too rather than only on the exterior tail below.
            updatePlayerSpaces(playerCapsule, frameTime: frameTime)
            return
        }

        var sceneChanged = props.integrateActorProps()
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
            runtimeStates.pruneRebuildState()
            coverage.discardStagedCells(outside: grid.desiredCells)
            if !actions.removals.isEmpty, !coverageTransitionActive {
                coverage.unload(actions.removals)
                sceneChanged = true
            }
            requests.append(contentsOf: coverage.requestsNearestFirst(actions.requests))
        }

        if builds.integrateOneBuild() {
            sceneChanged = true
        }
        if coverage.integrateDistantLOD(completedLOD) {
            sceneChanged = true
        }
        if sceneChanged {
            builds.recomposeAndSink()
        }
        residents.updateInteractionTarget(ray: interactionRay)
        if activate {
            residents.activateInteractionTarget()
        }
        builds.dispatchNextBuild()
        coverage.requestDistantLODIfNeeded()
        builds.emitCenterRegionsIfChanged()
        ambience.emitAmbienceContextIfNeeded()
        ambience.emitMusicContextIfNeeded()
        updatePlayerSpaces(playerCapsule, frameTime: frameTime)
    }

    /// Trigger volumes and automatic doors the player stands in, then the world systems.
    private func updatePlayerSpaces(_ capsule: PlayerCapsuleState?, frameTime: Float) {
        triggers.updateTriggerOccupancy(capsule)
        transitions.updateAutomaticDoors(feet: capsule?.feetPosition)
        navigation.advanceWorldSystems(frameTime: frameTime, player: capsule)
    }

    // MARK: - Integration
}

extension CellStreamer {}

// MARK: - Worldspace changes

extension CellStreamer {
    /// Moves the exterior to another worldspace at `camera`, for a teleport. The
    /// runner switches after the builds it already holds, whose results are dropped.
    public func enterWorldspace(_ editorID: String, camera: SceneCamera) {
        if let previous = interiorScene {
            interiorScene = nil
            doorState.interiorSourceDoor = nil
            interiorMutationSequence = 0
            triggers.emitCellDetached(previous)
            coverage.evictUnused(previous.assets)
        }
        residents.updateInteractionTarget(ray: nil)
        runner.enqueueWorldspaceChange(editorID)
        switchExterior(to: editorID, at: camera.walkFeetPosition ?? camera.eye)
        hasSeededCamera = true
        sink(props.viewScene(), camera)
        ambience.invalidateAmbienceContext()
        ambience.invalidateMusicContext()
    }

    /// Drops every exterior cell, staged cell, and the distant ring, then
    /// recenters the grid at `position` in `editorID`. The runner must already
    /// build in `editorID`, or have that change queued.
    func switchExterior(to editorID: String, at position: SIMD3<Float>) {
        builds.resetExterior(at: position)
        worldspaceEditorID = editorID
        events.onWorldspaceChanged(editorID)
    }

    /// Starts the exterior at `position` while no cell has framed the view yet,
    /// so a start picked in the main menu loads there and not at the launch cell.
    public func moveStart(to position: SIMD3<Float>) {
        guard !hasSeededCamera, activeBuild == nil, requestedLODCenter == nil else { return }
        builds.resetExterior(at: position)
        hasSeededCamera = true
    }
}

extension CellStreamer {
    public func noteDoorTransitionFailure() {
        doorState.doorTransitionFailureCount += 1
    }
}

extension CellStreamer {
    public var actors: ActorSteps {
        ActorSteps(streamer: self)
    }

    public var residents: ResidentSteps {
        ResidentSteps(streamer: self)
    }

    public var collision: CollisionSteps {
        CollisionSteps(streamer: self)
    }

    public var physics: PhysicsSteps {
        PhysicsSteps(streamer: self)
    }

    public var transitions: TransitionSteps {
        TransitionSteps(streamer: self)
    }

    public var runtimeStates: RuntimeStateSteps {
        RuntimeStateSteps(streamer: self)
    }

    public var props: PropSteps {
        PropSteps(streamer: self)
    }

    public var coverage: CoverageSteps {
        CoverageSteps(streamer: self)
    }

    public var triggers: TriggerSteps {
        TriggerSteps(streamer: self)
    }

    public var navigation: NavigationSteps {
        NavigationSteps(streamer: self)
    }

    public var builds: BuildSteps {
        BuildSteps(streamer: self)
    }

    public var ambience: AmbienceSteps {
        AmbienceSteps(streamer: self)
    }

    /// The NPC movers: walking, facing, resting, riding, and their saved state.
    public struct ActorSteps {
        let streamer: CellStreamer
    }

    /// The resident references, the interaction target, and activation.
    public struct ResidentSteps {
        let streamer: CellStreamer
    }

    /// Ground, water, and collision queries against the resident cells.
    public struct CollisionSteps {
        let streamer: CellStreamer
    }

    /// The dynamic bodies, water, and the moving collision of a frame.
    public struct PhysicsSteps {
        let streamer: CellStreamer
    }

    /// Door transitions, worldspace changes, and automatic doors.
    public struct TransitionSteps {
        let streamer: CellStreamer
    }

    /// The saved world state of resident references, enable parents, and hazards.
    public struct RuntimeStateSteps {
        let streamer: CellStreamer
    }

    /// Actor props and animated objects.
    public struct PropSteps {
        let streamer: CellStreamer
    }

    /// Which cells must load, in which order, and the counts that show it.
    public struct CoverageSteps {
        let streamer: CellStreamer
    }

    /// Trigger volumes and the Papyrus events of resident cells.
    public struct TriggerSteps {
        let streamer: CellStreamer
    }

    /// Path finding over the resident navigation meshes, and its overlay.
    public struct NavigationSteps {
        let streamer: CellStreamer
    }

    /// The music and ambient sound of the cells around the player.
    /// The build pipeline: dispatch, integrate, and recompose the resident cells.
    public struct BuildSteps {
        let streamer: CellStreamer
    }

    public struct AmbienceSteps {
        let streamer: CellStreamer
    }
}

/// The NPC movement engine, a part of the actor part.
struct CellNPCMovers {
    let streamer: CellStreamer
}
