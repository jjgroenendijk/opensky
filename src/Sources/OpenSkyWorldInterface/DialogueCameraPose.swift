import simd

/// One resolved frame: where to look from, what to look at, and what the
/// collision sweep did about it.
nonisolated public struct DialogueCameraPose: Equatable, Sendable {
    public let eye: SIMD3<Float>
    /// The point the camera is aimed at, which is the speaker's head.
    public let target: SIMD3<Float>
    public let yaw: Float
    public let pitch: Float
    /// Eye-to-target distance after the collision pull-in.
    public let distance: Float
    /// True when world geometry, rather than the framing rule, decided that
    /// distance.
    public let isCollisionLimited: Bool

    public init(
        eye: SIMD3<Float>,
        target: SIMD3<Float>,
        yaw: Float,
        pitch: Float,
        distance: Float,
        isCollisionLimited: Bool
    ) {
        self.eye = eye
        self.target = target
        self.yaw = yaw
        self.pitch = pitch
        self.distance = distance
        self.isCollisionLimited = isCollisionLimited
    }
}
