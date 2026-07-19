// Terrain-only player movement (milestone 4.1): capsule pose, gravity,
// grounded snap, slope limit, fixed/clamped stepping. Mesh collision lands in
// later M4 items; this controller accepts a generic ground-sample closure.

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

    static let walkSpeed: Float = 180
    static let runSpeed: Float = 360
    static let gravity: Float = 1400
    static let maximumSlopeDegrees: Float = 50
    static let fixedTimeStep: Float = 1 / 120
    static let maximumFrameTime: Float = 0.1
    static let groundSnapDistance: Float = 24

    let capsule: PlayerCapsule
    private(set) var feetPosition: SIMD3<Float>
    private(set) var verticalVelocity: Float = 0
    private(set) var isGrounded = false
    private var accumulatedTime: Float = 0

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
        accumulatedTime = 0
    }

    /// Integrates look once per frame, then translation through fixed 120 Hz
    /// steps. Frame contribution clamps to 100 ms; stalls cannot teleport or
    /// inject an unbounded gravity impulse. Residual time carries forward.
    mutating func update(
        camera: inout FreeFlyCamera,
        input: CameraInput,
        sampleGround: GroundSampler
    ) {
        camera.applyLook(lookRight: input.lookRight, lookUp: input.lookUp)
        let clampedTime = min(max(input.dt, 0), Self.maximumFrameTime)
        accumulatedTime += clampedTime
        while accumulatedTime + Float.ulpOfOne >= Self.fixedTimeStep {
            step(
                yaw: camera.yaw,
                input: input,
                dt: Self.fixedTimeStep,
                sampleGround: sampleGround
            )
            accumulatedTime -= Self.fixedTimeStep
        }
        camera.position = cameraPosition
    }

    private mutating func step(
        yaw: Float,
        input: CameraInput,
        dt: Float,
        sampleGround: GroundSampler
    ) {
        let forward = SIMD2<Float>(cosf(yaw), sinf(yaw))
        let right = SIMD2<Float>(sinf(yaw), -cosf(yaw))
        var direction = forward * input.moveForward + right * input.moveRight
        let magnitude = simd_length(direction)
        if magnitude > 1 {
            direction /= magnitude
        }

        let currentXY = SIMD2<Float>(feetPosition.x, feetPosition.y)
        let distance = (input.boost ? Self.runSpeed : Self.walkSpeed) * dt
        var candidateXY = currentXY + direction * distance
        if isBlockedSlope(at: candidateXY, direction: direction, sampleGround: sampleGround) {
            candidateXY = currentXY
        }
        feetPosition.x = candidateXY.x
        feetPosition.y = candidateXY.y

        verticalVelocity -= Self.gravity * dt
        feetPosition.z += verticalVelocity * dt
        guard let ground = sampleGround(candidateXY) else {
            isGrounded = false
            return
        }
        let separation = feetPosition.z - ground.height
        if separation <= 0 || (isGrounded && separation <= Self.groundSnapDistance) {
            feetPosition.z = ground.height
            verticalVelocity = 0
            isGrounded = isWalkable(ground.normal)
        } else {
            isGrounded = false
        }
    }

    private func isWalkable(_ normal: SIMD3<Float>) -> Bool {
        let minimumUp = cosf(MatrixMath.radians(fromDegrees: Self.maximumSlopeDegrees))
        return normal.z >= minimumUp
    }

    private func isBlockedSlope(
        at position: SIMD2<Float>,
        direction: SIMD2<Float>,
        sampleGround: GroundSampler
    ) -> Bool {
        guard
            isGrounded,
            simd_length_squared(direction) > .ulpOfOne,
            let candidate = sampleGround(position)
        else { return false }
        return !isWalkable(candidate.normal)
    }
}
