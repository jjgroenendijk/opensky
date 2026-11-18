// When a character swims, where it floats, and when it leaves the water. The same rule
// holds for the player and every NPC. See docs/engine/ground-and-water-contact.md#water.

nonisolated public enum SwimRule {
    /// Submersion at which swimming starts, and under which it may stop.
    public static let swimSubmersion: Float = 0.7
    /// Submersion at which a character counts as in water.
    public static let inWaterSubmersion: Float = 0.01
    /// Submersion at which the head is under water and the breath timer runs.
    public static let headUnderSubmersion: Float = 0.875
    /// The float point rests this far under the surface; deeper, buoyancy pushes up.
    public static let floatRestDepth: Float = 10
    /// A swimmer whose float point is this close to the surface may jump out.
    public static let surfaceJumpReach: Float = 350
    /// A jump out of the water reaches this many times the normal jump height.
    public static let surfaceJumpHeightScale: Float = 2

    /// The float level of every NPC and creature, and of the player in third person.
    public static let characterFloatLevel: Float = 1.6
    /// The float level of the player in first person.
    public static let firstPersonFloatLevel: Float = 1.3
    /// The float level of a character with the `WaterWalking` actor value.
    public static let waterWalkingFloatLevel: Float = 0.1

    /// How deep the feet are, as a fraction of the body height, from 0 to 1.
    /// Example: feet 96 units under the surface of a 128-unit body give 0.75.
    public static func submersion(surface: Float, feetHeight: Float, bodyHeight: Float) -> Float {
        guard surface.isFinite, bodyHeight > 0, surface > feetHeight else { return 0 }
        return min((surface - feetHeight) / bodyHeight, 1)
    }

    /// Whether the character swims in this step.
    /// Depth alone starts swimming; only shallow water with ground below ends it.
    /// A character that rises, such as after a jump out of the water, does not start.
    public static func swims(_ contact: SwimContact) -> Bool {
        guard contact.wasSwimming else {
            return !contact.isRising && contact.submersion >= swimSubmersion
        }
        if contact.hasGroundBelow {
            return contact.submersion >= swimSubmersion
        }
        return contact.submersion >= inWaterSubmersion
    }

    /// The height of the point on the body that floats near the surface.
    public static func floatPointHeight(
        feetHeight: Float,
        bodyHeight: Float,
        floatLevel: Float
    ) -> Float {
        feetHeight + 0.5 * bodyHeight * floatLevel
    }

    /// The feet height at which a still swimmer rests.
    public static func restingFeetHeight(
        surface: Float,
        bodyHeight: Float,
        floatLevel: Float
    ) -> Float {
        surface - floatRestDepth - 0.5 * bodyHeight * floatLevel
    }

    /// Whether a jump now ends swimming.
    public static func canJumpOut(surface: Float, floatPointHeight: Float) -> Bool {
        surface - floatPointHeight <= surfaceJumpReach
    }
}

/// What the swim rule reads for one step.
nonisolated public struct SwimContact: Equatable, Sendable {
    public var submersion: Float
    public var wasSwimming: Bool
    /// Walkable ground was found by the ground search below the feet.
    public var hasGroundBelow: Bool
    public var isRising: Bool

    public init(submersion: Float, wasSwimming: Bool, hasGroundBelow: Bool, isRising: Bool) {
        self.submersion = submersion
        self.wasSwimming = wasSwimming
        self.hasGroundBelow = hasGroundBelow
        self.isRising = isRising
    }
}
