// How fast a fighter closes in on its target, by distance band. The rule and its sources
// are in docs/engine/combat-approach.md.

import Foundation

/// A speed between walk and run: 1 is the actor's walk speed and 2 its run speed.
nonisolated public struct CombatPace: Equatable, Sendable {
    public static let walk = CombatPace(level: 1)
    public static let fastWalk = CombatPace(level: 1.33)
    public static let run = CombatPace(level: 2)

    public let level: Float

    public init(level: Float) {
        self.level = level.isFinite ? min(max(level, 1), 2) : 1
    }

    /// True for the half of the scale that plays the run.
    public var runs: Bool {
        level >= 1.5
    }

    /// The share of the way from walk speed to run speed.
    public var walkRunBlend: Float {
        level - 1
    }
}

nonisolated public enum CombatApproachRule {
    /// Where a style lies between the `Min` and `Max` radii: the Defensive Mult less the
    /// Offensive Mult, moved from -1...1 to 0...1.
    public static func radiusLevel(offensive: Float, defensive: Float) -> Float {
        let difference = defensive - offensive
        return difference.isFinite ? min(max((difference + 1) / 2, 0), 1) : 0.5
    }

    /// The pace at `distance`: run beyond the outer radius, fast walk down to the slow
    /// band, then a blend down to walk at the inner radius.
    public static func pace(
        distance: Float, inner: Float, outer: Float, slowdownDistance: Float
    ) -> CombatPace {
        if distance > outer {
            return .run
        }
        let band = max(slowdownDistance, 0)
        guard distance < inner + band, band > 0 else { return .fastWalk }
        let share = max(distance - inner, 0) / band
        return CombatPace(
            level: CombatPace.walk.level
                + (CombatPace.fastWalk.level - CombatPace.walk.level) * share
        )
    }
}
