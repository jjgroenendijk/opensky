// Whether a bow or crossbow kill cam plays, decided at the release before the arrow
// lands. See docs/engine/kill-cam.md#bow-and-spell-kill-cams-in-the-game.

import Foundation
import simd

/// What the release check reads about one shot.
nonisolated public struct RangedKillCamFacts: Equatable, Sendable {
    /// Hostile living actors fighting the player, the target included.
    public var enemiesInCombat = 1
    public var targetAlive = true
    public var hitKills = true
    /// The bow's draw, 0...1; nil for a crossbow, which skips the draw check.
    public var draw: Float?
    public var clearLine = true
    public var distance: Float = 0
    public var targetLevel: Int?
    public var playerLevel: Int?
    /// The player's health over its maximum.
    public var playerHealthShare: Float = 1
    /// A sneak shot from a bow or crossbow that the target has not detected.
    public var undetectedSneakShot = false
    /// The target is a hostile actor fighting the player.
    public var targetIsHostileThreat = true

    public init() {}
}

nonisolated public enum RangedKillCam {
    static let minimumDraw: Float = 0.8
    /// At this distance or more the chance check passes at once.
    static let sureDistance: Float = 2500
    static let lowHealthShare: Float = 0.05
    static let distanceDivisor: Float = 25
    static let chanceFloor: Float = 50
    static let lowLevelShare: Float = 0.3
    /// The arrow turns toward the target by at most this many degrees.
    public static let largestTurnDegrees: Float = 15

    /// The chance in percent, or nil when the check passes at once.
    public static func chance(_ facts: RangedKillCamFacts) -> Float? {
        if facts.distance >= sureDistance || facts.playerHealthShare < lowHealthShare {
            return nil
        }
        if let target = facts.targetLevel, let player = facts.playerLevel, target > player {
            return nil
        }
        var bonus: Float = facts.undetectedSneakShot ? 20 : facts.targetIsHostileThreat ? 0 : 10
        if
            let target = facts.targetLevel, let player = facts.playerLevel,
            Float(target) < lowLevelShare * Float(player)
        {
            bonus += 10
        }
        return max(facts.distance / distanceDivisor, chanceFloor) - bonus
    }

    /// Whether the shot plays a kill cam, with `roll` in 0 ..< 100.
    public static func plays(_ facts: RangedKillCamFacts, roll: Float) -> Bool {
        guard
            facts.enemiesInCombat <= 1, facts.targetAlive, facts.hitKills, facts.clearLine,
            facts.draw.map({ $0 >= minimumDraw }) ?? true
        else { return false }
        return chance(facts).map { roll < $0 } ?? true
    }
}
