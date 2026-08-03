// Fixed-step player movement: capsule pose, gravity, terrain grounding, static
// mesh collide-and-slide, slope limit, and bounded step response.

import simd

nonisolated enum CameraMovementMode: Equatable {
    case fly
    case walk
}

nonisolated struct PlayerCapsule: Equatable {
    /// Capsule radius in native Skyrim world units.
    let radius: Float
    /// Bottom-to-top extent.
    let height: Float
    /// Camera offset above capsule bottom.
    let eyeHeight: Float

    static let standard = PlayerCapsule(radius: 24, height: 128, eyeHeight: 112)
}

nonisolated struct WalkController {
    typealias GroundSampler = (SIMD2<Float>) -> TerrainGroundSample?
    typealias CollisionQuery = CapsuleWorldCollider.CandidateQuery
    /// Asked once per fixed step for that step's displacement (issue #188).
    /// Nil leaves the controller on its own input-derived movement, which is
    /// what walk mode did before a behavior graph existed.
    typealias StepPlanner = (LocomotionStepState) -> LocomotionStepPlan

    /// The world queries and the planner one fixed step runs against, bundled
    /// so the step signature stays inside the parameter cap.
    struct StepWorld {
        let sampleGround: GroundSampler
        let collisionQuery: CollisionQuery
        let plan: StepPlanner?
    }

    static let gravity: Float = 1400
    static let maximumSlopeDegrees: Float = 50
    static let fixedTimeStep: Float = 1 / 120
    static let maximumFrameTime: Float = 0.1
    static let groundSnapDistance: Float = 24
    /// How fast a swimmer may rise or sink, units per second. The capsule is
    /// held at the surface by a clamped correction rather than by buoyancy
    /// integration, so a swimmer cannot be launched by a deep step.
    static let maximumSwimVerticalSpeed: Float = 200

    let capsule: PlayerCapsule
    let configuration: PlayerMovementConfiguration
    private(set) var feetPosition: SIMD3<Float>
    private(set) var verticalVelocity: Float = 0
    private(set) var isGrounded = false
    private(set) var hasUnresolvedPenetration = false
    /// True while the last step resolved in water deep enough to swim. Gravity,
    /// ground snap, and step support are all suspended there.
    private(set) var isSwimming = false
    private var accumulatedTime: Float = 0
    var activeStepSupportHeight: Float?

    struct HorizontalMove {
        let result: CapsuleMoveResult
        let supportHeight: Float?
    }

    init(
        cameraPosition: SIMD3<Float>,
        capsule: PlayerCapsule = .standard,
        configuration: PlayerMovementConfiguration = .synthetic
    ) {
        self.capsule = capsule
        self.configuration = configuration
        feetPosition = cameraPosition - SIMD3<Float>(0, 0, capsule.eyeHeight)
    }

    var cameraPosition: SIMD3<Float> {
        feetPosition + SIMD3<Float>(0, 0, capsule.eyeHeight)
    }

    mutating func reset(cameraPosition: SIMD3<Float>) {
        feetPosition = cameraPosition - SIMD3<Float>(0, 0, capsule.eyeHeight)
        verticalVelocity = 0
        isGrounded = false
        hasUnresolvedPenetration = false
        isSwimming = false
        accumulatedTime = 0
        activeStepSupportHeight = nil
    }

    /// Integrates look once per frame, then translation through fixed 120 Hz
    /// steps. Frame contribution clamps to 100 ms; stalls cannot teleport or
    /// inject an unbounded gravity impulse. Residual time carries forward.
    mutating func update(
        camera: inout FreeFlyCamera,
        input: CameraInput,
        sampleGround: GroundSampler,
        collisionQuery: CollisionQuery = { _ in [] },
        plan: StepPlanner? = nil
    ) {
        camera.applyLook(lookRight: input.lookRight, lookUp: input.lookUp)
        let clampedTime = min(max(input.dt, 0), Self.maximumFrameTime)
        accumulatedTime += clampedTime
        // `StepWorld` stores the two queries, which needs them escaping; the
        // callers' closures are not, and none of them outlives this call, so
        // they are lent rather than promoted.
        withoutActuallyEscaping(sampleGround) { ground in
            withoutActuallyEscaping(collisionQuery) { query in
                let world = StepWorld(
                    sampleGround: ground, collisionQuery: query, plan: plan
                )
                while accumulatedTime + Float.ulpOfOne >= Self.fixedTimeStep {
                    step(yaw: camera.yaw, input: input, dt: Self.fixedTimeStep, world: world)
                    accumulatedTime -= Self.fixedTimeStep
                }
            }
        }
        camera.position = cameraPosition
    }

    private mutating func step(
        yaw: Float,
        input: CameraInput,
        dt: Float,
        world: StepWorld
    ) {
        let sampleGround = world.sampleGround
        let collisionQuery = world.collisionQuery
        let currentPosition = feetPosition
        let plan = world.plan?(LocomotionStepState(
            feetPosition: currentPosition,
            verticalVelocity: verticalVelocity,
            isGrounded: isGrounded,
            yaw: yaw,
            dt: dt
        )) ?? Self.plan(input: input, yaw: yaw, dt: dt, configuration: configuration)

        let currentXY = SIMD2<Float>(currentPosition.x, currentPosition.y)
        let direction = simd_length(plan.horizontalDisplacement) > 0
            ? simd_normalize(plan.horizontalDisplacement)
            : SIMD2<Float>()
        var candidateXY = currentXY + plan.horizontalDisplacement
        if
            !plan.isSwimming,
            isBlockedSlope(at: candidateXY, direction: direction, sampleGround: sampleGround)
        {
            candidateXY = currentXY
        }
        let collider = CapsuleWorldCollider(capsule: capsule)
        let horizontal = SIMD3<Float>(
            candidateXY.x - currentXY.x,
            candidateXY.y - currentXY.y,
            0
        )
        let horizontalMove = moveHorizontal(
            from: currentPosition,
            displacement: horizontal,
            collider: collider,
            collisionQuery: collisionQuery
        )
        let horizontalResult = horizontalMove.result
        feetPosition = horizontalResult.position
        activeStepSupportHeight = plan.isSwimming ? nil : horizontalMove.supportHeight
        hasUnresolvedPenetration = horizontalResult.hasUnresolvedPenetration

        if let impulse = plan.jumpImpulse, impulse > 0 {
            verticalVelocity = impulse
            isGrounded = false
            activeStepSupportHeight = nil
        }
        isSwimming = plan.isSwimming
        if let surface = plan.swimSurfaceHeight {
            swim(
                to: surface,
                wanted: plan.swimVerticalVelocity,
                collider: collider,
                dt: dt,
                collisionQuery: collisionQuery
            )
            return
        }
        resolveVerticalMovement(
            collider: collider,
            dt: dt,
            sampleGround: sampleGround,
            collisionQuery: collisionQuery
        )
    }

    /// The displacement walk mode produces on its own, with no planner
    /// attached: level input direction at the walk or run gait. Unchanged from
    /// what the controller did before item 14.5, and the reason attaching a
    /// bridge cannot double the movement — one of the two runs, never both.
    private static func plan(
        input: CameraInput,
        yaw: Float,
        dt: Float,
        configuration: PlayerMovementConfiguration
    ) -> LocomotionStepPlan {
        let forward = SIMD2<Float>(cosf(yaw), sinf(yaw))
        let right = SIMD2<Float>(sinf(yaw), -cosf(yaw))
        var direction = forward * input.moveForward + right * input.moveRight
        let magnitude = simd_length(direction)
        if magnitude > 1 {
            direction /= magnitude
        }
        let speed = input.boost ? configuration.runSpeed.value : configuration.walkSpeed.value
        var plan = LocomotionStepPlan()
        plan.horizontalDisplacement = direction * speed * dt
        plan.motionSource = direction == SIMD2<Float>() ? .idle : .configuredSpeed
        return plan
    }

    /// Vertical handling while swimming: no gravity, no ground snap, and no
    /// step support. The capsule is driven toward the depth its eye sits at the
    /// surface, or up and down at the swimmer's own request, both clamped to
    /// `maximumSwimVerticalSpeed` so nothing can be flung by a deep step.
    private mutating func swim(
        to surface: Float,
        wanted: Float,
        collider: CapsuleWorldCollider,
        dt: Float,
        collisionQuery: CollisionQuery
    ) {
        let floatingZ = surface - capsule.eyeHeight
        let correction = wanted != 0 ? wanted : (floatingZ - feetPosition.z) / dt
        verticalVelocity = min(
            max(correction, -Self.maximumSwimVerticalSpeed), Self.maximumSwimVerticalSpeed
        )
        let result = collider.move(
            from: feetPosition,
            displacement: SIMD3<Float>(0, 0, verticalVelocity * dt),
            query: collisionQuery
        )
        feetPosition = result.position
        hasUnresolvedPenetration = hasUnresolvedPenetration || result.hasUnresolvedPenetration
        // A swimmer resting on a shallow bottom is still grounded, which is
        // what lets it walk back out; nothing snaps it there.
        isGrounded = hasWalkableContact(result.contacts)
    }

    private mutating func resolveVerticalMovement(
        collider: CapsuleWorldCollider,
        dt: Float,
        sampleGround: GroundSampler,
        collisionQuery: CollisionQuery
    ) {
        if let supportHeight = activeStepSupportHeight {
            feetPosition.z = supportHeight
            verticalVelocity = 0
            isGrounded = true
            return
        }
        verticalVelocity -= Self.gravity * dt
        let verticalResult = collider.move(
            from: feetPosition,
            displacement: SIMD3<Float>(0, 0, verticalVelocity * dt),
            query: collisionQuery
        )
        feetPosition = verticalResult.position
        hasUnresolvedPenetration = hasUnresolvedPenetration
            || verticalResult.hasUnresolvedPenetration
        var grounded = hasWalkableContact(verticalResult.contacts)
        let hitCeiling = verticalResult.contacts.contains { $0.normal.z < -0.1 }
        if grounded, verticalVelocity <= 0 {
            verticalVelocity = 0
        } else if verticalVelocity > 0, hitCeiling {
            verticalVelocity = 0
        }

        let wasGrounded = isGrounded
        if let ground = sampleGround(SIMD2(feetPosition.x, feetPosition.y)) {
            let separation = feetPosition.z - ground.height
            let withinSnap = (wasGrounded || grounded)
                && separation <= Self.groundSnapDistance
            if isWalkable(ground.normal), separation <= 0 || withinSnap {
                feetPosition.z = ground.height
                verticalVelocity = 0
                grounded = true
            }
        }
        if !grounded, wasGrounded, verticalVelocity <= 0 {
            let snap = collider.move(
                from: feetPosition,
                displacement: SIMD3<Float>(0, 0, -Self.groundSnapDistance),
                query: collisionQuery
            )
            if hasWalkableContact(snap.contacts), snap.position.z <= feetPosition.z {
                feetPosition = snap.position
                verticalVelocity = 0
                grounded = true
                hasUnresolvedPenetration = hasUnresolvedPenetration
                    || snap.hasUnresolvedPenetration
            }
        }
        isGrounded = grounded
    }
}
