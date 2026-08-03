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
    /// every write and event is dropped rather than queued, so item 14.6 can
    /// attach a real graph without changing anything here.
    let graph: BehaviorGraphInstance?
    /// Water surface height at a world XY, or nil where the cell has no water.
    var sampleWater: ((SIMD2<Float>) -> Float?)?

    /// This frame's intent. The renderer writes it once per frame; every fixed
    /// step in that frame reads the same value.
    var intent: LocomotionIntent = .still

    private(set) var status: LocomotionStatus
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
        intent = .still
        status = LocomotionStatus(graphAvailable: graph != nil)
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

    /// Speed of one gait, units per second.
    func speed(of gait: LocomotionGait) -> Float {
        switch gait {
        case .walk: configuration.walkSpeed.value
        case .run: configuration.runSpeed.value
        case .sprint: configuration.sprintSpeed.value
        case .sneak: configuration.sneakSpeed.value
        case .swim: configuration.swimSpeed.value
        }
    }

    /// Level world-space movement direction, unit length or shorter.
    private func intentDirection(yaw: Float) -> SIMD2<Float> {
        let forward = SIMD2<Float>(cosf(yaw), sinf(yaw))
        let right = SIMD2<Float>(sinf(yaw), -cosf(yaw))
        var direction = forward * intent.moveForward + right * intent.moveRight
        let magnitude = simd_length(direction)
        if magnitude > 1 {
            direction /= magnitude
        }
        return direction
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

    private func advanceGraph(deltaTime: Float) -> BehaviorRootMotion? {
        guard let graph else { return nil }
        let result = graph.update(deltaTime: deltaTime)
        status.noteGraphUpdate(events: result.firedEvents)
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

    private func write(_ value: BehaviorVariableValue, to name: String) {
        guard let graph else { return }
        if graph.setVariable(value, named: name) {
            status.noteVariableWritten(name)
        } else {
            status.noteVariableMissing(name)
        }
    }

    private func raise(_ name: String) {
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

    // MARK: - Math

    /// Movement direction as the graph wants it: radians away from facing,
    /// positive to the left, zero straight ahead, and zero when standing still.
    static func graphDirection(of direction: SIMD2<Float>, yaw: Float) -> Float {
        guard direction != SIMD2<Float>() else { return 0 }
        return shortestAngle(from: yaw, to: atan2f(direction.y, direction.x))
    }

    /// Signed angle from one heading to another, in (-pi, pi].
    static func shortestAngle(from start: Float, to end: Float) -> Float {
        var delta = (end - start).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi {
            delta -= 2 * .pi
        } else if delta <= -.pi {
            delta += 2 * .pi
        }
        return delta
    }
}
