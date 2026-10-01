// Where input, the behavior graph and the capsule controller meet. Each step has one
// horizontal source (graph root travel if extracted, else gait speed); the controller
// owns vertical motion. No vanilla locomotion clip has extracted motion, so vanilla
// uses gait speed; the branch keys on `BehaviorRootMotion.isExtracted`, not a speed
// threshold. See docs/engine/walk-mode.md.

import OpenSkyBehavior
import OpenSkyCombatInterface
import OpenSkyPhysics
import OpenSkyRendering
import simd

/// One frame of player intent, in the form the bridge consumes. Filled from
/// `CameraInput` once per frame and held across the fixed steps that frame
/// drives, exactly like the rest of `CameraInput`.
nonisolated public struct LocomotionIntent: Equatable, Sendable {
    /// Along the level view forward vector, [-1, 1].
    public var moveForward: Float = 0
    /// Along the level view right vector, [-1, 1].
    public var moveRight: Float = 0
    /// Run key (Shift) held.
    public var run = false
    /// Sprint key held.
    public var sprint = false
    /// Sneak toggle state.
    public var sneak = false
    /// One jump press, consumed by the first step that can act on it.
    public var jump = false

    public static let still = LocomotionIntent()
}

nonisolated public final class LocomotionBridge {
    /// Swim enter and exit depths of the capsule bottom below water: swim at about chest
    /// deep, so wading stays walking. They differ so the mode cannot flicker. Ours; no
    /// GMST states them.
    public static let swimEnterDepth: Float = 90
    public static let swimExitDepth: Float = 70

    public let configuration: PlayerMovementConfiguration
    /// The graph this bridge feeds, or nil. A nil graph is a supported
    /// configuration and not a degraded one: locomotion still resolves, and
    /// every write and event is dropped rather than queued, which is why item
    /// 14.6 can attach a real graph mid-session with nothing to replay.
    public private(set) var graph: BehaviorGraphInstance?
    /// The first-person graph, run beside the third-person one. Nil until attached, or on
    /// an install with no first-person files; then no arms are drawn.
    public private(set) var firstPersonGraph: BehaviorGraphInstance?
    /// Water surface height at a world XY, or nil where the cell has no water.
    public var sampleWater: ((SIMD2<Float>) -> Float?)?
    /// The pose the last graph update produced, published here because only this steps
    /// the graph, on the simulation clock (PlayerAnimationPlayback.swift).
    public let pose = PlayerPoseBuffer()
    /// The same, for the first-person rig. A separate buffer because the two
    /// graphs pose two different skeletons and a shared one would hand the
    /// arms the body's bones.
    public let firstPersonPose = PlayerPoseBuffer()

    /// This frame's intent. The renderer writes it once per frame; every fixed
    /// step in that frame reads the same value.
    public var intent: LocomotionIntent = .still

    /// This frame's melee intent, kept out of `intent` because the fixed step never reads
    /// it; the melee runtime does at frame rate. One input path still feeds both.
    public private(set) var meleeIntent: MeleeIntent = .still

    /// This frame's archery intent, like `meleeIntent`. `hasBowEquipped` stays false here;
    /// the app fills it from the equipped set.
    public private(set) var archeryIntent: ArcheryIntent = .still

    /// A forced gait, or nil (`World > Player & Locomotion > Dev Controls`). It forces the
    /// graph inputs and gait speed only; water, gravity and collision are untouched, so a
    /// forced `swim` swims on dry floor.
    public var forcedGait: LocomotionGait?

    public private(set) var status: LocomotionStatus
    /// Third-person graph events awaiting consumers. Only that graph feeds it, or every
    /// footstep would play twice. See LocomotionGraphEventQueue.swift.
    public let graphEvents: LocomotionGraphEventQueue
    /// The footstep director's and melee runtime's cursors into `graphEvents`, so both see
    /// every event. Registered in `init` (the queue drops what no cursor can read) and
    /// owned here, so a replaced bridge cannot leave a stale cursor.
    public let footstepEventConsumer: LocomotionGraphEventQueue.Consumer
    public let meleeEventConsumer: LocomotionGraphEventQueue.Consumer
    /// The archery runtime's cursor.
    public let archeryEventConsumer: LocomotionGraphEventQueue.Consumer
    /// The ragdoll runtime's cursor.
    public let ragdollEventConsumer: LocomotionGraphEventQueue.Consumer

    private var previousYaw: Float?
    private var wasMoving = false
    private var wasSprinting = false
    private var wasSneaking = false
    private var wasSwimming = false
    /// The swim edge the graph was last told about. Kept apart from
    /// `wasSwimming`, which drives the water-depth hysteresis: a forced swim
    /// gait must reach the graph without also telling `resolveSwim` that the
    /// capsule is already in water and may leave at the shallower threshold.
    private var wasGraphSwimming = false
    private var wasGrounded = true
    /// False until a step sees the capsule standing. A reset leaves `isGrounded` false,
    /// and reporting that change would fake a landing on every teleport, so ground events
    /// start once standing.
    private var hasGroundSample = false
    private var isAirborneFromJump = false
    private var pendingJump = false

    public init(
        configuration: PlayerMovementConfiguration,
        graph: BehaviorGraphInstance? = nil,
        sampleWater: ((SIMD2<Float>) -> Float?)? = nil
    ) {
        let events = LocomotionGraphEventQueue()
        graphEvents = events
        footstepEventConsumer = events.addConsumer()
        meleeEventConsumer = events.addConsumer()
        archeryEventConsumer = events.addConsumer()
        ragdollEventConsumer = events.addConsumer()
        self.configuration = configuration
        self.graph = graph
        self.sampleWater = sampleWater
        status = LocomotionStatus(graphAvailable: graph != nil)
        seedPerspectiveVariables()
    }

    /// Takes this frame's intent from the drained camera input. Jump is latched
    /// here rather than consumed, so a press between two rendered frames still
    /// reaches a fixed step.
    public func acceptFrame(_ input: CameraInput) {
        intent = LocomotionIntent(
            moveForward: input.moveForward,
            moveRight: input.moveRight,
            run: input.boost,
            sprint: input.sprint,
            sneak: input.sneak,
            jump: input.jump
        )
        meleeIntent = MeleeIntent(
            attack: input.attack,
            block: input.block,
            toggleWeaponDrawn: input.toggleWeaponDrawn
        )
        archeryIntent = ArcheryIntent(drawing: input.attackHeld, deltaTime: input.dt)
        if input.jump {
            pendingJump = true
        }
    }

    /// Plans one fixed step: writes engine state into the graph, advances the
    /// graph, and answers with the displacement the controller should attempt.
    ///
    /// A zero-length step is a total no-op — no variable write, no event, no
    /// graph update, no latch consumed — because a paused frame must advance
    /// nothing and fire nothing (docs/engine/menu-mode.md).
    public func plan(_ state: LocomotionStepState) -> LocomotionStepPlan {
        guard state.dt > 0 else {
            status.lastPlan = .still
            return .still
        }
        let swim = resolveSwim(at: state)
        let gait = resolveGait(swimming: swim != nil)
        let direction = intentDirection(yaw: state.yaw)
        let moving = direction != SIMD2<Float>()
        let jumpImpulse = resolveJump(state: state, swimming: swim != nil)

        writeVariables(state: state, gait: gait, direction: direction, moving: moving)
        raiseEdgeEvents(
            moving: moving, gait: gait, swimming: swim != nil || gait == .swim,
            jumping: jumpImpulse != nil, grounded: state.isGrounded
        )
        let rootMotion = advanceGraph(deltaTime: state.dt)

        var plan = LocomotionStepPlan()
        plan.jumpImpulse = jumpImpulse
        plan.swimSurfaceHeight = swim
        plan.swimVerticalVelocity = swimVerticalVelocity(swimming: swim != nil)
        let resolved = resolveDisplacement(
            rootMotion: rootMotion,
            direction: direction,
            gait: gait,
            state: state
        )
        plan.horizontalDisplacement = resolved.displacement
        plan.motionSource = resolved.source

        previousYaw = state.yaw
        wasMoving = moving
        wasSprinting = gait == .sprint
        wasSneaking = isSneakingNow
        wasSwimming = swim != nil
        wasGraphSwimming = swim != nil || gait == .swim
        wasGrounded = state.isGrounded
        hasGroundSample = hasGroundSample || state.isGrounded
        status.update(gait: gait, plan: plan, state: state, waterSurface: swim)
        return plan
    }

    /// Attaches or detaches the graph and resets edge state, so a new graph hears no old
    /// transitions. Called once `0_master.hkx` has loaded.
    public func attach(graph: BehaviorGraphInstance?) {
        self.graph = graph
        reset()
    }

    /// Attaches (or detaches) the first-person graph. Separate from `attach`
    /// because the two load independently: an install can ship a usable
    /// third-person set and a broken `_1stperson` one, and that has to leave
    /// the player walking rather than take the whole graph down.
    public func attachFirstPerson(graph: BehaviorGraphInstance?) {
        firstPersonGraph = graph
        reset()
    }

    /// Forgets the edge state so the next step raises no stale transition.
    /// Called when walk mode is entered or the player is teleported.
    public func reset() {
        previousYaw = nil
        wasMoving = false
        wasSprinting = false
        wasSneaking = false
        wasSwimming = false
        wasGraphSwimming = false
        wasGrounded = true
        hasGroundSample = false
        isAirborneFromJump = false
        pendingJump = false
        graphEvents.clear()
        intent = .still
        meleeIntent = .still
        archeryIntent = .still
        status = LocomotionStatus(
            graphAvailable: graph != nil,
            firstPersonGraphAvailable: firstPersonGraph != nil
        )
        pose.clear()
        firstPersonPose.clear()
        seedPerspectiveVariables()
    }

    /// Lends a write of the status snapshot to the satellite file.
    ///
    /// `private(set)` is scoped to this file, and the first-person half of the
    /// bridge lives in `LocomotionBridgeFirstPerson.swift`. Lending one
    /// narrow mutation is what keeps the setter closed to everyone else rather
    /// than widening it for the whole module.
    public func updateStatus(_ change: (inout LocomotionStatus) -> Void) {
        change(&status)
    }

    // MARK: - Resolution

    /// The water surface to swim against, or nil to stay on land. Hysteresis:
    /// entering needs `swimEnterDepth`, leaving needs the shallower
    /// `swimExitDepth`.
    private func resolveSwim(at state: LocomotionStepState) -> Float? {
        guard
            let sampleWater,
            let surface = sampleWater(SIMD2(state.feetPosition.x, state.feetPosition.y)),
            surface.isFinite
        else { return nil }
        let depth = surface - state.feetPosition.z
        let threshold = wasSwimming ? Self.swimExitDepth : Self.swimEnterDepth
        return depth >= threshold ? surface : nil
    }

    private func resolveGait(swimming: Bool) -> LocomotionGait {
        if let forcedGait {
            return forcedGait
        }
        if swimming {
            return .swim
        }
        if intent.sneak {
            return .sneak
        }
        if intent.sprint {
            return .sprint
        }
        return intent.run ? .run : .walk
    }

    /// The one-shot takeoff impulse, or nil. A jump needs solid ground: it is
    /// dropped in the air rather than queued, which is what stops a held key
    /// from turning into a second jump the moment the capsule lands.
    private func resolveJump(state: LocomotionStepState, swimming: Bool) -> Float? {
        guard pendingJump else { return nil }
        pendingJump = false
        guard state.isGrounded, !swimming else { return nil }
        isAirborneFromJump = true
        return configuration.jumpTakeoffSpeed.value
    }

    /// The step's horizontal displacement and where it came from.
    private func resolveDisplacement(
        rootMotion: BehaviorRootMotion?,
        direction: SIMD2<Float>,
        gait: LocomotionGait,
        state: LocomotionStepState
    ) -> (displacement: SIMD2<Float>, source: LocomotionMotionSource) {
        // `isExtracted`, not a speed threshold: whether the clip carries travel is a
        // property of the file, not of this step's root movement.
        if let rootMotion, rootMotion.isExtracted {
            let local = SIMD2<Float>(rootMotion.translation.x, rootMotion.translation.y)
            // Root travel is in the character's own frame; the character faces
            // the level camera yaw, so it rotates by the same angle the input
            // direction is built from.
            let forward = SIMD2<Float>(cosf(state.yaw), sinf(state.yaw))
            let right = SIMD2<Float>(sinf(state.yaw), -cosf(state.yaw))
            return (forward * local.y + right * local.x, .rootMotion)
        }
        guard direction != SIMD2<Float>() else { return (SIMD2<Float>(), .idle) }
        return (direction * speed(of: gait) * state.dt, .configuredSpeed)
    }

    // MARK: - Graph

    /// Steps every attached graph and returns the third-person root travel. The
    /// first-person graph's root motion is dropped, so the capsule is driven once.
    private func advanceGraph(deltaTime: Float) -> BehaviorRootMotion? {
        advanceFirstPersonGraph(deltaTime: deltaTime)
        guard let graph else { return nil }
        let result = graph.update(deltaTime: deltaTime)
        status.noteGraphUpdate(events: result.firedEvents)
        graphEvents.enqueue(result.firedEvents)
        pose.publish(result.bones)
        return result.rootMotion
    }

    private func writeVariables(
        state: LocomotionStepState,
        gait: LocomotionGait,
        direction: SIMD2<Float>,
        moving: Bool
    ) {
        let turnDelta = previousYaw.map { Self.shortestAngle(from: $0, to: state.yaw) } ?? 0
        write(.real(moving ? speed(of: gait) : 0), to: LocomotionGraphNames.speed)
        write(.real(moving ? speed(of: gait) : 0), to: LocomotionGraphNames.speedSampled)
        write(
            .real(Self.graphDirection(of: direction, yaw: state.yaw)),
            to: LocomotionGraphNames.direction
        )
        write(.real(turnDelta), to: LocomotionGraphNames.turnDelta)
        write(.bool(gait == .sprint), to: LocomotionGraphNames.isSprinting)
        write(.bool(gait == .sneak), to: LocomotionGraphNames.isSneaking)
        write(.int(gait == .sneak ? 1 : 0), to: LocomotionGraphNames.isInSneak)
        write(.bool(isAirborneFromJump || !state.isGrounded), to: LocomotionGraphNames.inJumpState)
        write(.real(configuration.walkSpeed.value), to: LocomotionGraphNames.speedWalk)
        write(.real(configuration.runSpeed.value), to: LocomotionGraphNames.speedRun)
    }

    /// Raises the transitions this step crossed, in a fixed order so a step
    /// that changes several things at once still produces the same event
    /// sequence on every run.
    private func raiseEdgeEvents(
        moving: Bool,
        gait: LocomotionGait,
        swimming: Bool,
        jumping: Bool,
        grounded: Bool
    ) {
        if moving != wasMoving {
            raise(moving ? LocomotionGraphNames.moveStart : LocomotionGraphNames.moveStop)
        }
        let sprinting = gait == .sprint
        if sprinting != wasSprinting {
            raise(sprinting ? LocomotionGraphNames.sprintStart : LocomotionGraphNames.sprintStop)
        }
        let sneaking = isSneakingNow
        if sneaking != wasSneaking {
            raise(sneaking ? LocomotionGraphNames.sneakStart : LocomotionGraphNames.sneakStop)
        }
        if swimming != wasGraphSwimming {
            raise(swimming ? LocomotionGraphNames.swimStart : LocomotionGraphNames.swimStop)
        }
        if jumping {
            raise(LocomotionGraphNames.jumpUp)
        } else if hasGroundSample, grounded, !wasGrounded {
            // Landing is the controller's observation, not the graph's: the
            // graph is told that the capsule arrived.
            isAirborneFromJump = false
            raise(LocomotionGraphNames.jumpLand)
        } else if hasGroundSample, !grounded, wasGrounded {
            raise(LocomotionGraphNames.jumpFall)
        }
    }
}
