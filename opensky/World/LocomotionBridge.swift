// The character-controller bridge (issue #188): the one place where player
// input, the behavior graph, and the capsule controller meet.
//
// Movement authority, stated once and enforced by the shape of the types:
//
// * Horizontal motion has exactly one source per fixed step. The bridge picks
//   it — the graph's own root travel when the data carries any, the resolved
//   gait speed otherwise — and hands `WalkController` a displacement. The
//   controller never derives horizontal motion of its own while a planner is
//   attached, so nothing can integrate the same axis twice.
// * Vertical motion belongs to the controller: gravity, ground snap, step
//   support, and the slope rule. The bridge can inject one takeoff impulse and
//   can say "this step happens in water"; it cannot integrate height.
// * The controller's resolved position and grounded flag come back in on the
//   next step and become graph variables, which closes the loop.
//
// Vanilla data never takes the root-motion branch, and that is a measurement
// rather than an assumption: not one of the 2,654 HKX files under
// `meshes\actors\character\` carries an `hkaAnimatedReferenceFrame`, and every
// `hkaSplineCompressedAnimation` in the locomotion clips leaves
// `m_extractedMotion` null. Skyrim's locomotion clips animate in place and the
// engine supplies the travel; the graph is a consumer of `Speed` and
// `Direction`, not the source of movement. The root-motion branch stays because
// a data set that does carry extracted motion has to drive the capsule from it
// rather than be silently ignored. See docs/engine/walk-mode.md.

import simd

/// One frame of player intent, in the form the bridge consumes. Filled from
/// `CameraInput` once per frame and held across the fixed steps that frame
/// drives, exactly like the rest of `CameraInput`.
nonisolated struct LocomotionIntent: Equatable {
    /// Along the level view forward vector, [-1, 1].
    var moveForward: Float = 0
    /// Along the level view right vector, [-1, 1].
    var moveRight: Float = 0
    /// Run key (Shift) held.
    var run = false
    /// Sprint key held.
    var sprint = false
    /// Sneak toggle state.
    var sneak = false
    /// One jump press, consumed by the first step that can act on it.
    var jump = false

    static let still = LocomotionIntent()
}

/// Which gait the bridge resolved for a step. Sneak outranks sprint, which
/// outranks run: crouching cancels a sprint in vanilla rather than stacking
/// with it, and swimming replaces all three.
nonisolated enum LocomotionGait: String, Equatable, Sendable {
    case walk
    case run
    case sprint
    case sneak
    case swim
}

nonisolated final class LocomotionBridge {
    /// How much horizontal root travel per second counts as the graph actually
    /// driving the character.
    ///
    /// In-place vanilla clips still jitter the root bone by a fraction of a
    /// unit per step; a 3-second drive of `mt_behavior.hkx` accumulated 0.04
    /// units of travel in total, about 1 unit/s at its noisiest step. Ten
    /// units per second sits an order of magnitude above that jitter and two
    /// orders below the 100 unit/s walk gait, so it separates the two cases
    /// without being sensitive to where the threshold sits.
    static let rootMotionSpeedFloor: Float = 10

    /// How far the capsule bottom must sit below the water surface before
    /// swimming starts, and how far it must rise before it stops. The enter
    /// depth is most of the capsule (128 units tall, eye at 112): the player
    /// swims once the water is about chest deep, and wading stays walking. The
    /// two differ so a capsule bobbing on the threshold cannot flip modes every
    /// step. Both are OpenSky measurements against the capsule dimensions; no
    /// GMST in the install states either.
    static let swimEnterDepth: Float = 90
    static let swimExitDepth: Float = 70

    let configuration: PlayerMovementConfiguration
    /// The graph this bridge feeds, or nil. A nil graph is a supported
    /// configuration and not a degraded one: locomotion still resolves, and
    /// every write and event is dropped rather than queued, which is why item
    /// 14.6 can attach a real graph mid-session with nothing to replay.
    private(set) var graph: BehaviorGraphInstance?
    /// The first-person graph, run beside the third-person one over the
    /// install's `_1stperson` behavior set (issue #190). Nil until the app
    /// attaches it, and nil forever on an install that ships no first-person
    /// files, both of which are supported rather than degraded: the arms are
    /// then simply not drawn. See LocomotionBridgeFirstPerson.swift.
    private(set) var firstPersonGraph: BehaviorGraphInstance?
    /// Water surface height at a world XY, or nil where the cell has no water.
    var sampleWater: ((SIMD2<Float>) -> Float?)?
    /// The pose the last graph update produced, for whoever is drawing the
    /// body (issue #189). Published here rather than sampled elsewhere because
    /// this is the only place the graph is stepped, and the graph steps on the
    /// simulation clock: see PlayerAnimationPlayback.swift.
    let pose = PlayerPoseBuffer()
    /// The same, for the first-person rig. A separate buffer because the two
    /// graphs pose two different skeletons and a shared one would hand the
    /// arms the body's bones.
    let firstPersonPose = PlayerPoseBuffer()

    /// This frame's intent. The renderer writes it once per frame; every fixed
    /// step in that frame reads the same value.
    var intent: LocomotionIntent = .still

    private(set) var status: LocomotionStatus
    /// Third-person graph events awaiting a consumer (issue #352). Only the
    /// third-person graph feeds it: both graphs run the same locomotion clips
    /// and therefore fire the same triggers, so draining both would play every
    /// footstep twice. See LocomotionGraphEventQueue.swift.
    let graphEvents = LocomotionGraphEventQueue()
    private var previousYaw: Float?
    private var wasMoving = false
    private var wasSprinting = false
    private var wasSneaking = false
    private var wasSwimming = false
    private var wasGrounded = true
    private var isAirborneFromJump = false
    private var pendingJump = false

    init(
        configuration: PlayerMovementConfiguration,
        graph: BehaviorGraphInstance? = nil,
        sampleWater: ((SIMD2<Float>) -> Float?)? = nil
    ) {
        self.configuration = configuration
        self.graph = graph
        self.sampleWater = sampleWater
        status = LocomotionStatus(graphAvailable: graph != nil)
        seedPerspectiveVariables()
    }

    /// Takes this frame's intent from the drained camera input. Jump is latched
    /// here rather than consumed, so a press between two rendered frames still
    /// reaches a fixed step.
    func acceptFrame(_ input: CameraInput) {
        intent = LocomotionIntent(
            moveForward: input.moveForward,
            moveRight: input.moveRight,
            run: input.boost,
            sprint: input.sprint,
            sneak: input.sneak,
            jump: input.jump
        )
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
    func plan(_ state: LocomotionStepState) -> LocomotionStepPlan {
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
            moving: moving, gait: gait, swimming: swim != nil, jumping: jumpImpulse != nil,
            grounded: state.isGrounded
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
        wasSneaking = intent.sneak
        wasSwimming = swim != nil
        wasGrounded = state.isGrounded
        status.update(gait: gait, plan: plan, state: state, waterSurface: swim)
        return plan
    }

    /// Attaches (or detaches) the graph this bridge feeds, resetting the edge
    /// state so the newly attached graph is not told about transitions that
    /// happened before it existed (issue #189). The app calls this once, when
    /// the install's own `0_master.hkx` has loaded.
    func attach(graph: BehaviorGraphInstance?) {
        self.graph = graph
        reset()
    }

    /// Attaches (or detaches) the first-person graph. Separate from `attach`
    /// because the two load independently: an install can ship a usable
    /// third-person set and a broken `_1stperson` one, and that has to leave
    /// the player walking rather than take the whole graph down.
    func attachFirstPerson(graph: BehaviorGraphInstance?) {
        firstPersonGraph = graph
        reset()
    }

    /// Forgets the edge state so the next step raises no stale transition.
    /// Called when walk mode is entered or the player is teleported.
    func reset() {
        previousYaw = nil
        wasMoving = false
        wasSprinting = false
        wasSneaking = false
        wasSwimming = false
        wasGrounded = true
        isAirborneFromJump = false
        pendingJump = false
        graphEvents.clear()
        intent = .still
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
    func updateStatus(_ change: (inout LocomotionStatus) -> Void) {
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

    /// Ascend on jump, descend on sneak, hold depth otherwise. Both keys are
    /// already bound, so swimming needs no third binding.
    private func swimVerticalVelocity(swimming: Bool) -> Float {
        guard swimming else { return 0 }
        let rate = configuration.swimSpeed.value * 0.5
        if intent.jump {
            return rate
        }
        return intent.sneak ? -rate : 0
    }

    /// The step's horizontal displacement and where it came from.
    private func resolveDisplacement(
        rootMotion: BehaviorRootMotion?,
        direction: SIMD2<Float>,
        gait: LocomotionGait,
        state: LocomotionStepState
    ) -> (displacement: SIMD2<Float>, source: LocomotionMotionSource) {
        if let rootMotion {
            let local = SIMD2<Float>(rootMotion.translation.x, rootMotion.translation.y)
            if simd_length(local) / state.dt >= Self.rootMotionSpeedFloor {
                // Root travel is in the character's own frame; the character
                // faces the level camera yaw, so it rotates by the same angle
                // the input direction is built from.
                let forward = SIMD2<Float>(cosf(state.yaw), sinf(state.yaw))
                let right = SIMD2<Float>(sinf(state.yaw), -cosf(state.yaw))
                return (forward * local.y + right * local.x, .rootMotion)
            }
        }
        guard direction != SIMD2<Float>() else { return (SIMD2<Float>(), .idle) }
        return (direction * speed(of: gait) * state.dt, .configuredSpeed)
    }

    // MARK: - Graph

    /// Steps every attached graph and answers with the third-person one's root
    /// travel.
    ///
    /// Only the third-person graph can move the character. The first-person
    /// graph is stepped with the same inputs and publishes its own pose, but
    /// its root motion is deliberately dropped: two graphs both allowed to
    /// drive the capsule would integrate the same axis twice, and the arms are
    /// a view of the movement rather than a source of it (see the file
    /// comment's movement-authority rule).
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

    /// Writes one variable to every attached graph. Both see identical inputs
    /// by construction: there is one call site per variable and it fans out
    /// here, so the two graphs cannot be fed different state.
    private func write(_ value: BehaviorVariableValue, to name: String) {
        writeToFirstPersonGraph(value, to: name)
        guard let graph else { return }
        if graph.setVariable(value, named: name) {
            status.noteVariableWritten(name)
        } else {
            status.noteVariableMissing(name)
        }
    }

    private func raise(_ name: String) {
        raiseOnFirstPersonGraph(name)
        guard let graph else { return }
        if graph.raiseEvent(named: name) {
            status.noteEventRaised(name)
        } else {
            status.noteEventMissing(name)
        }
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
        if intent.sneak != wasSneaking {
            raise(intent.sneak ? LocomotionGraphNames.sneakStart : LocomotionGraphNames.sneakStop)
        }
        if swimming != wasSwimming {
            raise(swimming ? LocomotionGraphNames.swimStart : LocomotionGraphNames.swimStop)
        }
        if jumping {
            raise(LocomotionGraphNames.jumpUp)
        } else if grounded, !wasGrounded {
            // Landing is the controller's observation, not the graph's: the
            // graph is told that the capsule arrived.
            isAirborneFromJump = false
            raise(LocomotionGraphNames.jumpLand)
        } else if !grounded, wasGrounded, !jumping {
            raise(LocomotionGraphNames.jumpFall)
        }
    }
}
