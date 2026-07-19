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

    static let walkSpeed: Float = 180
    static let runSpeed: Float = 360
    static let gravity: Float = 1400
    static let maximumSlopeDegrees: Float = 50
    static let fixedTimeStep: Float = 1 / 120
    static let maximumFrameTime: Float = 0.1
    static let groundSnapDistance: Float = 24
    static let stepHeight: Float = 32

    let capsule: PlayerCapsule
    private(set) var feetPosition: SIMD3<Float>
    private(set) var verticalVelocity: Float = 0
    private(set) var isGrounded = false
    private(set) var hasUnresolvedPenetration = false
    private var accumulatedTime: Float = 0
    var activeStepSupportHeight: Float?

    struct HorizontalMove {
        let result: CapsuleMoveResult
        let supportHeight: Float?
    }

    init(cameraPosition: SIMD3<Float>, capsule: PlayerCapsule = .standard) {
        self.capsule = capsule
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
        collisionQuery: CollisionQuery = { _ in [] }
    ) {
        camera.applyLook(lookRight: input.lookRight, lookUp: input.lookUp)
        let clampedTime = min(max(input.dt, 0), Self.maximumFrameTime)
        accumulatedTime += clampedTime
        while accumulatedTime + Float.ulpOfOne >= Self.fixedTimeStep {
            step(
                yaw: camera.yaw,
                input: input,
                dt: Self.fixedTimeStep,
                sampleGround: sampleGround,
                collisionQuery: collisionQuery
            )
            accumulatedTime -= Self.fixedTimeStep
        }
        camera.position = cameraPosition
    }

    private mutating func step(
        yaw: Float,
        input: CameraInput,
        dt: Float,
        sampleGround: GroundSampler,
        collisionQuery: CollisionQuery
    ) {
        let forward = SIMD2<Float>(cosf(yaw), sinf(yaw))
        let right = SIMD2<Float>(sinf(yaw), -cosf(yaw))
        var direction = forward * input.moveForward + right * input.moveRight
        let magnitude = simd_length(direction)
        if magnitude > 1 {
            direction /= magnitude
        }

        let currentPosition = feetPosition
        let currentXY = SIMD2<Float>(currentPosition.x, currentPosition.y)
        let distance = (input.boost ? Self.runSpeed : Self.walkSpeed) * dt
        var candidateXY = currentXY + direction * distance
        if isBlockedSlope(at: candidateXY, direction: direction, sampleGround: sampleGround) {
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
        activeStepSupportHeight = horizontalMove.supportHeight
        hasUnresolvedPenetration = horizontalResult.hasUnresolvedPenetration

        resolveVerticalMovement(
            collider: collider,
            dt: dt,
            sampleGround: sampleGround,
            collisionQuery: collisionQuery
        )
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
