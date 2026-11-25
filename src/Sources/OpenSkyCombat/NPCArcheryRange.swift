// Where an NPC archer stands and when it shoots, as pure rules. Read from the game
// program; each constant is a game setting the masters do not override.
// See docs/engine/archery.md#npc-archers.

import Foundation

/// One archer's distances, shot chance, and draw hold, from its combat style.
nonisolated struct NPCArcheryRange: Equatable, Sendable {
    /// `fCombatMaximumProjectileRange` and `fCombatProjectileMaxRangeMult`.
    static let maximumProjectileRange: Float = 4096
    static let projectileMaxRangeMult: Float = 0.9
    /// `fCombatRangedDistance`: a longest shot past it makes the weapon ranged.
    static let rangedDistance: Float = 1024
    /// `fCombatRangedMinimumRange`.
    static let rangedMinimumRange: Float = 256
    /// `fCombatMaximumOptimalRangeMin`, `Mid`, and `Max`.
    static let optimalMinimum: Float = 1024
    static let optimalMiddle: Float = 1280
    static let optimalMaximum: Float = 1536
    static let maximumBuffer: Float = 512
    /// `fCombatBackoffMinDistanceMult`.
    static let backOffMult: Float = 0.75
    /// `fCombatRangedAttackChanceMin`, `Max`, `LastAttackBonus`, and `LastAttackBonusTime`.
    static let attackChance: (min: Float, max: Float) = (0.05, 1)
    static let lastAttackBonus: Float = 0.5
    static let lastAttackBonusSeconds: Float = 10
    /// `fCombatRangedAttackHoldTimeMin`, `Max`, `AbsoluteMin`, and `MinDistance`.
    static let holdTimeMinimum: Float = 0.25
    static let holdTimeMaximum: Float = 1.5
    static let holdTimeAbsoluteMinimum: Float = 0.1
    static let holdMinDistance: Float = 256

    /// The longest shot it takes, the closest it wants the target, and where it stands.
    let longest: Float
    let minimum: Float
    let preferred: Float
    /// The style's offensive multiplier.
    let offense: Float
    /// What the game adds to each distance: the archer's radius.
    let radius: Float

    init(style: CombatStyleTuning, radius: Float, ballisticRange: Float = .infinity) {
        let reach = radius.isFinite ? max(0, radius) : 0
        let shot = min(
            Self.maximumProjectileRange,
            max(0, ballisticRange.isFinite ? ballisticRange : .greatestFiniteMagnitude)
                * Self.projectileMaxRangeMult
        )
        longest = shot
        let ranged = shot > Self.rangedDistance ? Self.rangedMinimumRange : 0
        minimum = min(ranged, max(0, shot - Self.rangedMinimumRange)) + reach
        preferred = Self.preferredDistance(style: style) + reach
        offense = style.offensiveMultiplier.isFinite ? max(0, style.offensiveMultiplier) : 0
        self.radius = reach
    }

    /// From the defensive less the offensive multiplier: -1 stands at the minimum of the
    /// optimal range, 0 at its middle, and 1 at its maximum.
    static func preferredDistance(style: CombatStyleTuning) -> Float {
        let lean = style.defensiveMultiplier - style.offensiveMultiplier
        let x = lean.isFinite ? min(max(lean, -1), 1) : 0
        return x <= 0
            ? optimalMinimum + (optimalMiddle - optimalMinimum) * (x + 1)
            : optimalMiddle + (optimalMaximum - optimalMiddle) * x
    }

    /// Past this distance the archer walks back towards `preferred`.
    var farthest: Float {
        min(preferred + Self.maximumBuffer, longest)
    }

    /// Closer than this the archer steps back to `minimum`.
    var backOffDistance: Float {
        Self.backOffMult * minimum
    }

    /// The chance to loose a shot, which grows with the time since the last one.
    func shotChance(secondsSinceShot: Float) -> Float {
        let base = Self.attackChance.min + (Self.attackChance.max - Self.attackChance.min) * offense
        let waited = secondsSinceShot.isFinite ? max(0, secondsSinceShot) : Self
            .lastAttackBonusSeconds
        let share = min(waited / Self.lastAttackBonusSeconds, 1)
        return base + Self.lastAttackBonus * base * share
    }

    /// The longest the archer holds a full draw: shorter for a bolder style, and the
    /// shortest when the target is close.
    func holdCeiling(distance: Float) -> Float {
        let close = distance <= Self.holdMinDistance + radius
        let boldness = close ? 1 : min(offense, 1)
        return Self.holdTimeMaximum + (Self.holdTimeMinimum - Self.holdTimeMaximum) * boldness
    }

    /// The hold for a `unit` draw from [0, 1): uniform from the absolute minimum up to
    /// the ceiling.
    func hold(distance: Float, unit: Float) -> Float {
        let ceiling = max(Self.holdTimeAbsoluteMinimum, holdCeiling(distance: distance))
        return Self.holdTimeAbsoluteMinimum + (ceiling - Self.holdTimeAbsoluteMinimum) * unit
    }
}
