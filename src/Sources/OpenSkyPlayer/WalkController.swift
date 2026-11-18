// Fixed-step player movement: capsule pose, gravity, terrain grounding, static
// mesh collide-and-slide, slope limit, and bounded step response.
// See docs/engine/ground-and-water-contact.md.

public import OpenSkyFormatsESM
public import OpenSkyPhysics
public import OpenSkyRenderCore
import OpenSkyRendering
public import OpenSkyWorldInterface
import simd

nonisolated public struct WalkController: Sendable {
    public typealias GroundSampler = (SIMD2<Float>) -> TerrainGroundSample?
    public typealias CollisionQuery = CapsuleWorldCollider.CandidateQuery
    /// Asked once per fixed step for that step's displacement.
    /// Nil leaves the controller on its own input-derived movement, which is
    /// what walk mode did before a behavior graph existed.
    public typealias StepPlanner = (LocomotionStepState) -> LocomotionStepPlan

    /// The world queries and the planner one fixed step runs against, bundled
    /// so the step signature stays inside the parameter cap.
    public struct StepWorld {
        public let sampleGround: GroundSampler
        public let collisionQuery: CollisionQuery
        public let plan: StepPlanner?
    }

    static let gravity = PhysicsStep.gravity
    static let maximumSlopeDegrees = PhysicsStep.maximumSlopeDegrees
    static let fixedTimeStep = PhysicsStep.fixedTimeStep
    public static let maximumFrameTime = PhysicsStep.maximumFrameTime
    /// How far below the feet the ground search looks while on the ground: 1 physics unit.
    static let groundProbeDepth: Float = 69.99

    public let capsule: PlayerCapsule
    public let configuration: PlayerMovementConfiguration
    public internal(set) var feetPosition: SIMD3<Float>
    /// Whether a step may go from the first point to the second; nil moves freely.
    public var mayMove: (@Sendable (SIMD2<Float>, SIMD2<Float>) -> Bool)?
    /// The last update held the player back at a `mayMove` edge.
    public private(set) var isHeldAtEdge = false
    public internal(set) var verticalVelocity: Float = 0
    /// Horizontal speed from a trap or a push, units per second. It fades on the ground.
    public internal(set) var knockback = SIMD2<Float>()
    /// The velocity of a heavy moving body that carries or pushes the capsule this frame.
    public var carryVelocity = SIMD3<Float>()
    public internal(set) var isGrounded = false
    public internal(set) var hasUnresolvedPenetration = false
    /// True while the last step resolved in water deep enough to swim. Buoyancy
    /// replaces gravity there, and step support is suspended.
    public internal(set) var isSwimming = false
    /// The normal of the walkable ground the last step found; nil off the ground.
    public internal(set) var groundNormal: SIMD3<Float>?
    /// The MATT material of whatever the capsule is currently standing on:
    /// the terrain texture under the feet, or the material of the
    /// collision shape it rests against. Nil while airborne, and nil on a
    /// surface that names no material. This is the argument the footstep chain
    /// was missing — the impact table is keyed by it.
    public internal(set) var groundMaterial: FormID?
    private var accumulatedTime: Float = 0
    /// Seconds of one fixed step. A far NPC takes longer steps, so a walk that steps
    /// less often also runs fewer steps.
    public var stepTime = PhysicsStep.fixedTimeStep
    /// The feet one fixed step before `feetPosition`; drawing blends from here.
    private var previousFeetPosition: SIMD3<Float>
    public var activeStepSupport: CapsuleStepSupport?
    /// The highest feet height of the current fall; nil on the ground and in water.
    var fallPeakZ: Float?
    /// The last fall that ended on the ground and nobody took yet.
    public internal(set) var landing: WalkLanding?

    struct HorizontalMove: Sendable {
        let result: CapsuleMoveResult
        let support: CapsuleStepSupport?
    }

    public init(
        cameraPosition: SIMD3<Float>,
        capsule: PlayerCapsule = .standard,
        configuration: PlayerMovementConfiguration = .synthetic
    ) {
        self.capsule = capsule
        self.configuration = configuration
        feetPosition = cameraPosition - SIMD3<Float>(0, 0, capsule.eyeHeight)
        previousFeetPosition = feetPosition
    }

    public mutating func reset(cameraPosition: SIMD3<Float>) {
        feetPosition = cameraPosition - SIMD3<Float>(0, 0, capsule.eyeHeight)
        previousFeetPosition = feetPosition
        verticalVelocity = 0
        isGrounded = false
        hasUnresolvedPenetration = false
        isSwimming = false
        groundNormal = nil
        groundMaterial = nil
        accumulatedTime = 0
        activeStepSupport = nil
        knockback = SIMD2<Float>()
        fallPeakZ = nil
        landing = nil
    }

    /// Integrates look once per frame, then translation through fixed 120 Hz
    /// steps. Frame contribution clamps to 100 ms; stalls cannot teleport or
    /// inject an unbounded gravity impulse. Residual time carries forward.
    public mutating func update(
        camera: inout FreeFlyCamera,
        input: CameraInput,
        sampleGround: GroundSampler,
        collisionQuery: CollisionQuery = { _ in [] },
        plan: StepPlanner? = nil
    ) {
        camera.applyLook(lookRight: input.lookRight, lookUp: input.lookUp)
        let clampedTime = min(max(input.dt, 0), Self.maximumFrameTime)
        accumulatedTime += clampedTime
        isHeldAtEdge = false
        // `StepWorld` stores the two queries, which needs them escaping; the
        // callers' closures are not, and none of them outlives this call, so
        // they are lent rather than promoted.
        withoutActuallyEscaping(sampleGround) { ground in
            withoutActuallyEscaping(collisionQuery) { query in
                let world = StepWorld(
                    sampleGround: ground, collisionQuery: query, plan: plan
                )
                while accumulatedTime + Float.ulpOfOne >= stepTime {
                    previousFeetPosition = feetPosition
                    stepTrackingFall(yaw: camera.yaw, input: input, world: world)
                    accumulatedTime -= stepTime
                }
            }
        }
        camera.position = cameraPosition
    }

    mutating func step(
        yaw: Float,
        input: CameraInput,
        dt: Float,
        world: StepWorld
    ) {
        let sampleGround = Self.remembering(world.sampleGround)
        let collisionQuery = world.collisionQuery
        let currentPosition = feetPosition
        let plan = world.plan?(LocomotionStepState(
            feetPosition: currentPosition,
            verticalVelocity: verticalVelocity,
            isGrounded: isGrounded,
            yaw: yaw,
            dt: dt,
            bodyHeight: capsule.height
        )) ?? Self.plan(input: input, yaw: yaw, dt: dt, configuration: configuration)

        let currentXY = SIMD2<Float>(currentPosition.x, currentPosition.y)
        var candidateXY = currentXY + plan.horizontalDisplacement + pushStep(dt: dt)
        holdAtEdge(&candidateXY, from: currentXY)
        wallOffSteepTerrain(&candidateXY, from: currentPosition, sampleGround: sampleGround)
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
        activeStepSupport = plan.isSwimming ? nil : horizontalMove.support
        hasUnresolvedPenetration = horizontalResult.hasUnresolvedPenetration

        if let impulse = plan.jumpImpulse, impulse > 0 {
            verticalVelocity = impulse
            isGrounded = false
            groundNormal = nil
            groundMaterial = nil
            activeStepSupport = nil
        }
        isSwimming = plan.isSwimming
        let contact = ContactWorld(
            collider: collider, sampleGround: sampleGround, collisionQuery: collisionQuery
        )
        if let surface = plan.swimSurfaceHeight {
            swim(
                SwimStep(
                    surface: surface,
                    wantedVelocity: plan.swimVerticalVelocity,
                    floatLevel: plan.swimFloatLevel
                ),
                dt: dt,
                world: contact
            )
            return
        }
        resolveVerticalMovement(
            dt: dt,
            slopeDrop: groundSlopeDrop(moved: feetPosition - currentPosition),
            world: contact
        )
    }
}

nonisolated extension WalkController {
    /// Walk mode's own displacement with no planner: level input at walk or run speed.
    /// Only one of this and the bridge runs, so movement cannot double.
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
        let speed = input.isRunning ? configuration.runSpeed.value : configuration.walkSpeed.value
        var plan = LocomotionStepPlan()
        plan.horizontalDisplacement = direction * speed * dt
        plan.motionSource = direction == SIMD2<Float>() ? .idle : .configuredSpeed
        return plan
    }

    /// A step `mayMove` refuses keeps the feet where they are.
    private mutating func holdAtEdge(_ candidate: inout SIMD2<Float>, from current: SIMD2<Float>) {
        guard let mayMove, candidate != current, !mayMove(current, candidate) else { return }
        candidate = current
        isHeldAtEdge = true
    }

    /// Where to draw the feet: between the last two steps, by the time left
    /// over. A display frame rarely holds a whole number of steps, so drawing
    /// the last step alone makes the view jump by a step now and then.
    public var drawnFeetPosition: SIMD3<Float> {
        let blend = min(max(accumulatedTime / stepTime, 0), 1)
        return simd_mix(previousFeetPosition, feetPosition, SIMD3(repeating: blend))
    }

    public var cameraPosition: SIMD3<Float> {
        feetPosition + SIMD3<Float>(0, 0, capsule.eyeHeight)
    }

    public var drawnCameraPosition: SIMD3<Float> {
        drawnFeetPosition + SIMD3<Float>(0, 0, capsule.eyeHeight)
    }
}
