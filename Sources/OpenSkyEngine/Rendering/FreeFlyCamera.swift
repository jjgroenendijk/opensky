// Free-fly camera (todo 2.8): a pose in Skyrim's Z-up world (position + yaw +
// pitch) that produces a view matrix and integrates per-frame input. Pure math
// — no AppKit — so orientation, pitch clamp, movement direction and speed are
// unit-testable. The AppKit input capture lives in the view layer
// (`CameraInputState` + the MTKView responder); it hands this type a
// `CameraInput` snapshot each frame. See docs/engine/free-fly-camera.md.

import OpenSkyFormats
import simd

/// One frame of camera input, already resolved to axis magnitudes. Movement
/// axes are in [-1, 1]; look deltas are raw pointer deltas in points (the
/// camera applies its own sensitivity/sign). `dt` is seconds since the last
/// update. Pure value — the view layer fills it from NSEvents.
nonisolated public struct CameraInput: Sendable {
    /// Along the view forward vector (+1 = W, -1 = S).
    public var moveForward: Float = 0
    /// Along the horizontal right vector (+1 = D, -1 = A).
    public var moveRight: Float = 0
    /// Along world up +Z (+1 = E/up, -1 = Q/down).
    public var moveUp: Float = 0
    /// Pointer delta, points, +x = pointer moved right.
    public var lookRight: Float = 0
    /// Pointer delta, points, +y = pointer moved up (view looks up).
    public var lookUp: Float = 0
    /// Shift held -> speed boost. In walk mode this is run rather than walk.
    public var boost = false
    /// Sprint key held (issue #188). Walk mode only; fly mode ignores it.
    public var sprint = false
    /// Sneak mode, a toggle rather than a held key, so the value is the state
    /// the toggle currently sits in and not an edge.
    public var sneak = false
    /// One-shot jump request, latched by the input state until a frame drains it.
    public var jump = false
    /// One-shot request to advance the camera mode one step around the
    /// fly -> walk -> third-person cycle (issue #189).
    public var cycleCameraMode = false
    /// One-shot attack request, latched like jump (issue #195). Walk mode
    /// only; fly mode ignores it.
    public var attack = false
    /// The same button as a *level* rather than an edge (issue #196). A melee
    /// swing is a press and a bow draw is a hold, so the same binding has to
    /// report both: melee reads `attack`, archery reads this.
    public var attackHeld = false
    /// Block key held, a level rather than an edge — the melee runtime raises
    /// `blockStart` and `blockStop` on the changes.
    public var block = false
    /// One-shot draw/sheath request. One binding for both directions, because
    /// vanilla binds one key and the graph knows which way it is going.
    public var toggleWeaponDrawn = false
    /// Seconds elapsed since the previous update.
    public var dt: Float = 0
}

/// Camera pose + free-fly integration. Yaw rotates about world +Z (0 -> +X
/// east, +pi/2 -> +Y north); pitch elevates the view (+ looks up), clamped shy
/// of straight up/down so the view direction never aligns with world up (that
/// degenerates `lookAt`). Conventions: docs/decisions/coordinates.md.
nonisolated public struct FreeFlyCamera: Sendable {
    public var position: SIMD3<Float>
    public var yaw: Float
    public var pitch: Float

    /// Pitch limit (~89 deg): keeps forward off the world-up axis so the view
    /// basis stays well-conditioned.
    public static let maxPitch = MatrixMath.radians(fromDegrees: 89)

    /// Base translation speed. Skyrim exterior cell = 4096 units; ~1800
    /// units/s crosses one in ~2.3 s — seconds, not minutes
    /// (docs/decisions/coordinates.md scale).
    public static let baseSpeed: Float = 1800

    /// Shift multiplier over `baseSpeed`.
    public static let boostMultiplier: Float = 3.5

    /// Radians of look per point of pointer motion.
    public static let lookSensitivity: Float = 0.0025

    public static let worldUp = SIMD3<Float>(0, 0, 1)

    public init(position: SIMD3<Float>, yaw: Float, pitch: Float) {
        self.position = position
        self.yaw = yaw
        self.pitch = Self.clampPitch(pitch)
    }

    /// Seeds the pose from a framing `SceneCamera` so the free-fly view starts
    /// exactly where the injected camera framed the scene. Forward =
    /// eye -> target; yaw/pitch are recovered from it (degenerate straight-down
    /// framing falls back to yaw 0).
    public init(framing camera: SceneCamera) {
        let direction = camera.target - camera.eye
        let length = simd_length(direction)
        let forward = length > .ulpOfOne ? direction / length : SIMD3<Float>(1, 0, 0)
        position = camera.eye
        yaw = atan2f(forward.y, forward.x)
        pitch = Self.clampPitch(asinf(max(-1, min(1, forward.z))))
    }

    /// Unit view direction from yaw/pitch (Z-up world space).
    public var forward: SIMD3<Float> {
        let cosPitch = cosf(pitch)
        return SIMD3<Float>(cosPitch * cosf(yaw), cosPitch * sinf(yaw), sinf(pitch))
    }

    /// Horizontal right vector (strafing stays level regardless of pitch).
    /// Matches `cross(forward, worldUp)` for level forward: yaw 0 -> (0,-1,0).
    public var right: SIMD3<Float> {
        SIMD3<Float>(sinf(yaw), -cosf(yaw), 0)
    }

    /// Right-handed view matrix looking down the forward vector, world up +Z.
    public func viewMatrix() -> float4x4 {
        MatrixMath.lookAt(eye: position, target: position + forward, up: Self.worldUp)
    }

    /// Rotates the view by a pointer delta. Pointer right turns the view right
    /// (yaw decreases in this right-handed Z-up basis); pointer up raises pitch.
    /// Pitch is clamped.
    public mutating func applyLook(lookRight: Float, lookUp: Float) {
        yaw -= lookRight * Self.lookSensitivity
        pitch = Self.clampPitch(pitch + lookUp * Self.lookSensitivity)
    }

    /// Translates along forward/right/world-up by the input axes for `dt`
    /// seconds. Combined direction is normalized so diagonal motion is not
    /// faster; Shift applies the boost multiplier.
    public mutating func applyMove(
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
    public mutating func update(_ input: CameraInput) {
        applyLook(lookRight: input.lookRight, lookUp: input.lookUp)
        applyMove(
            forwardAxis: input.moveForward,
            rightAxis: input.moveRight,
            upAxis: input.moveUp,
            boost: input.boost,
            dt: input.dt
        )
    }

    /// Keeps a pitch shy of straight up and straight down, where `lookAt`
    /// degenerates. Internal rather than private because the dialogue camera
    /// aims itself at a point instead of integrating input (issue #427) and has
    /// to land inside the same bound this camera integrates within, or the two
    /// would disagree about what a legal view direction is.
    public static func clampPitch(_ pitch: Float) -> Float {
        max(-maxPitch, min(maxPitch, pitch))
    }
}
