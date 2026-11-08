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

    /// Halfway up the capsule.
    public var centreHeight: Float {
        Self.centreHeight(height: height)
    }

    public static func centreHeight(height: Float) -> Float {
        height / 2
    }

    /// Halfway up to the eyes: the torso, where a spell aims and where light is read.
    public var torsoHeight: Float {
        Self.torsoHeight(eyeHeight: eyeHeight)
    }

    public static func torsoHeight(eyeHeight: Float) -> Float {
        eyeHeight / 2
    }

    /// A capsule that is a ball of `radius`, for a probe that asks whether a point is free.
    public static func ball(radius: Float) -> PlayerCapsule {
        PlayerCapsule(radius: radius, height: radius * 2, eyeHeight: radius)
    }
}
