// The upright capsule the player and NPC movers collide as.

nonisolated public struct PlayerCapsule: Equatable, Sendable {
    /// Capsule radius in native Skyrim world units.
    public let radius: Float
    /// Bottom-to-top extent.
    public let height: Float
    /// Camera offset above capsule bottom.
    public let eyeHeight: Float

    public init(radius: Float, height: Float, eyeHeight: Float) {
        self.radius = radius
        self.height = height
        self.eyeHeight = eyeHeight
    }

    public static let standard = PlayerCapsule(radius: 24, height: 128, eyeHeight: 112)
}
