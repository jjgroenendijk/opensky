// Free-fly camera (todo 2.8): a pose in Skyrim's Z-up world (position + yaw +
// pitch) that produces a view matrix and integrates per-frame input. Pure math
// — no AppKit — so orientation, pitch clamp, movement direction and speed are
// unit-testable. The AppKit input capture lives in the view layer
// (`CameraInputState` + the MTKView responder); it hands this type a
// `CameraInput` snapshot each frame. See docs/engine/free-fly-camera.md.

import simd

/// One frame of camera input, already resolved to axis magnitudes. Movement
/// axes are in [-1, 1]; look deltas are raw pointer deltas in points (the
/// camera applies its own sensitivity/sign). `dt` is seconds since the last
/// update. Pure value — the view layer fills it from NSEvents.
nonisolated struct CameraInput {
    /// Along the view forward vector (+1 = W, -1 = S).
    var moveForward: Float = 0
    /// Along the horizontal right vector (+1 = D, -1 = A).
    var moveRight: Float = 0
    /// Along world up +Z (+1 = E/up, -1 = Q/down).
    var moveUp: Float = 0
    /// Pointer delta, points, +x = pointer moved right.
    var lookRight: Float = 0
    /// Pointer delta, points, +y = pointer moved up (view looks up).
    var lookUp: Float = 0
    /// Shift held -> speed boost.
    var boost = false
    /// Seconds elapsed since the previous update.
    var dt: Float = 0
}

/// Camera pose + free-fly integration. Yaw rotates about world +Z (0 -> +X
/// east, +pi/2 -> +Y north); pitch elevates the view (+ looks up), clamped shy
/// of straight up/down so the view direction never aligns with world up (that
/// degenerates `lookAt`). Conventions: docs/decisions/coordinates.md.
nonisolated struct FreeFlyCamera {
    var position: SIMD3<Float>
    var yaw: Float
    var pitch: Float

    /// Pitch limit (~89 deg): keeps forward off the world-up axis so the view
    /// basis stays well-conditioned.
    static let maxPitch = MatrixMath.radians(fromDegrees: 89)

    /// Base translation speed. Skyrim exterior cell = 4096 units; ~1800
    /// units/s crosses one in ~2.3 s — seconds, not minutes
    /// (docs/decisions/coordinates.md scale).
    static let baseSpeed: Float = 1800

    /// Shift multiplier over `baseSpeed`.
    static let boostMultiplier: Float = 3.5

    /// Radians of look per point of pointer motion.
    static let lookSensitivity: Float = 0.0025

    static let worldUp = SIMD3<Float>(0, 0, 1)

    init(position: SIMD3<Float>, yaw: Float, pitch: Float) {
        self.position = position
        self.yaw = yaw
        self.pitch = Self.clampPitch(pitch)
    }

    /// Seeds the pose from a framing `SceneCamera` so the free-fly view starts
    /// exactly where the injected camera framed the scene. Forward =
    /// eye -> target; yaw/pitch are recovered from it (degenerate straight-down
    /// framing falls back to yaw 0).
    init(framing camera: SceneCamera) {
        let direction = camera.target - camera.eye
        let length = simd_length(direction)
        let forward = length > .ulpOfOne ? direction / length : SIMD3<Float>(1, 0, 0)
        position = camera.eye
        yaw = atan2f(forward.y, forward.x)
        pitch = Self.clampPitch(asinf(max(-1, min(1, forward.z))))
    }

    /// Unit view direction from yaw/pitch (Z-up world space).
    var forward: SIMD3<Float> {
        let cosPitch = cosf(pitch)
        return SIMD3<Float>(cosPitch * cosf(yaw), cosPitch * sinf(yaw), sinf(pitch))
    }

    /// Horizontal right vector (strafing stays level regardless of pitch).
    /// Matches `cross(forward, worldUp)` for level forward: yaw 0 -> (0,-1,0).
    var right: SIMD3<Float> {
        SIMD3<Float>(sinf(yaw), -cosf(yaw), 0)
    }

    /// Right-handed view matrix looking down the forward vector, world up +Z.
    func viewMatrix() -> float4x4 {
        MatrixMath.lookAt(eye: position, target: position + forward, up: Self.worldUp)
    }

    /// Rotates the view by a pointer delta. Pointer right turns the view right
    /// (yaw decreases in this right-handed Z-up basis); pointer up raises pitch.
    /// Pitch is clamped.
    mutating func applyLook(lookRight: Float, lookUp: Float) {
        yaw -= lookRight * Self.lookSensitivity
        pitch = Self.clampPitch(pitch + lookUp * Self.lookSensitivity)
    }

    /// Translates along forward/right/world-up by the input axes for `dt`
    /// seconds. Combined direction is normalized so diagonal motion is not
    /// faster; Shift applies the boost multiplier.
    mutating func applyMove(
        forwardAxis: Float,
        rightAxis: Float,
        upAxis: Float,
        boost: Bool,
        dt: Float
    ) {
        let direction = forward * forwardAxis + right * rightAxis + Self.worldUp * upAxis
        let magnitude = simd_length(direction)
        guard magnitude > .ulpOfOne else { return }
        let speed = Self.baseSpeed * (boost ? Self.boostMultiplier : 1)
        position += direction / magnitude * speed * dt
    }

    /// Applies one input frame: look first (so movement uses the new heading),
    /// then translation.
    mutating func update(_ input: CameraInput) {
        applyLook(lookRight: input.lookRight, lookUp: input.lookUp)
        applyMove(
            forwardAxis: input.moveForward,
            rightAxis: input.moveRight,
            upAxis: input.moveUp,
            boost: input.boost,
            dt: input.dt
        )
    }

    private static func clampPitch(_ pitch: Float) -> Float {
        max(-maxPitch, min(maxPitch, pitch))
    }
}
