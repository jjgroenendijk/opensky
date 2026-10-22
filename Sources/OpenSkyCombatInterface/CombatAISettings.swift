// The game's combat AI settings that OpenSky's combat mind reads: the Confidence break-off
// strengths, the per-actor confidence nudge, the flee distance, and how far an ally may
// drift from its leader. No source says how the game uses them, so each use is OpenSky's
// reading (docs/engine/combat-behavior.md#game-settings).

import Foundation
import OpenSkyGameData

nonisolated public struct CombatAISettings: Equatable, Sendable {
    /// `fConfidenceCautious`, `fConfidenceAverage`, `fConfidenceBrave`: an actor of that
    /// Confidence breaks off when its strength over its target's falls below the value.
    public var cautiousStrength: Float = 0.375
    public var averageStrength: Float = 0.15
    public var braveStrength: Float = 0.0375
    /// `fCombatConfidenceModifierMin` and `...Max`: the range of the per-actor nudge.
    public var confidenceModifierMin: Float = -0.25
    public var confidenceModifierMax: Float = 1
    /// `fFleeDistanceInterior` and `fFleeDistanceExterior`: how far a fleeing actor runs.
    public var fleeDistanceInterior: Float = 3000
    public var fleeDistanceExterior: Float = 5000
    /// `fCombatDistance`: the base combat spacing, in units.
    public var combatDistance: Float = 141
    /// `fCombatFollowRadiusMult` and `fCombatTeammateFollowRadiusMult`: an ally farther
    /// than `combatDistance` times this from its leader walks back.
    public var followRadiusMult: Float = 3
    public var teammateFollowRadiusMult: Float = 3
    /// `fCombatAdvanceInnerRadiusMin`, `...Mid`, `...Max`: how far a caster backs off before
    /// it casts, picked by the style's defense.
    public var advanceInnerRadius = CombatRadii(low: 0, mid: 0, high: 256)
    /// `fCombatAdvanceOuterRadiusMin`, `...Mid`, `...Max`: inside this an approach walks,
    /// picked by the style's offense.
    public var advanceOuterRadius = CombatRadii(low: 128, mid: 256, high: 512)
    /// `fCombatAbsoluteMaxRangeMult`: past reach times this, a weapon is out of range.
    public var absoluteMaxRangeMult: Float = 4
    /// `fCombatCurrentWeaponAbsoluteMaxRangeMult`: the weapon in use keeps to reach times this.
    public var currentWeaponAbsoluteMaxRangeMult: Float = 1.25
    /// `fAIUseWeaponDistance`: no ranged attack starts farther than this.
    public var useWeaponDistance: Float = 15000
    /// `iAICombatRestoreHealthPercentage`: an NPC heals itself below this share of health.
    public var restoreHealthPercentage = 60
    /// `fAIShoutMinAimSeconds`, `fAIShoutToleranceDegrees`, `fAIShoutRetryDelaySeconds`.
    public var shoutMinAimSeconds: Float = 2
    public var shoutToleranceDegrees: Float = 5
    public var shoutRetryDelaySeconds: Float = 4
    /// `fCombatOrbitDistance`: how far a flying actor circles from its target.
    public var orbitDistance: Float = 4000
    /// `fCombatHoverTimeMin`, `fCombatPerchAttackTimeMin`, `fCombatGroundAttackTimeMin`,
    /// `...Max`: the times of a flying actor's air, perch, and ground stages.
    public var hoverTimeMin: Float = 5.5
    public var perchAttackTimeMin: Float = 4
    public var groundAttackTimeMin: Float = 8
    public var groundAttackTimeMax: Float = 17

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fConfidenceCautious", into: &settings, \.cautiousStrength)
        store.read("fConfidenceAverage", into: &settings, \.averageStrength)
        store.read("fConfidenceBrave", into: &settings, \.braveStrength)
        store.read("fCombatConfidenceModifierMin", into: &settings, \.confidenceModifierMin)
        store.read("fCombatConfidenceModifierMax", into: &settings, \.confidenceModifierMax)
        store.read("fFleeDistanceInterior", into: &settings, \.fleeDistanceInterior)
        store.read("fFleeDistanceExterior", into: &settings, \.fleeDistanceExterior)
        store.read("fCombatDistance", into: &settings, \.combatDistance)
        store.read("fCombatFollowRadiusMult", into: &settings, \.followRadiusMult)
        store.read("fCombatTeammateFollowRadiusMult", into: &settings, \.teammateFollowRadiusMult)
        settings.readRanges(store: store)
        return settings
    }

    /// The nudge range, ordered and finite even when a plugin sets min above max.
    public var confidenceModifierRange: ClosedRange<Float> {
        let low = confidenceModifierMin.isFinite ? confidenceModifierMin : 0
        let high = confidenceModifierMax.isFinite ? confidenceModifierMax : 0
        return min(low, high) ... max(low, high)
    }

    /// The strength below which an actor of `confidence` (1 cautious to 3 brave) breaks
    /// off. A nudged confidence between two levels blends their values.
    public func breakOffStrength(confidence: Float) -> Float {
        let level = confidence.isFinite ? min(max(confidence, 1), 3) : 2
        let points = [cautiousStrength, averageStrength, braveStrength]
        let lower = min(Int(level) - 1, 1)
        let blend = level - Float(lower + 1)
        return points[lower] + (points[lower + 1] - points[lower]) * blend
    }

    /// How far a fleeing actor runs, by where the fight is.
    public func fleeDistance(interior: Bool) -> Float {
        max(0, interior ? fleeDistanceInterior : fleeDistanceExterior)
    }

    /// How far an ally may drift from its leader; the player's allies use the teammate value.
    public func followDistance(leaderIsPlayer: Bool) -> Float {
        let mult = leaderIsPlayer ? teammateFollowRadiusMult : followRadiusMult
        let distance = combatDistance * mult
        return distance.isFinite ? max(distance, 0) : 0
    }

    /// `settings` with this flee distance. The fight ends `fleeMargin` beyond it, the same
    /// margin OpenSky's own numbers keep, so a flee the navmesh cuts short is retried.
    public func applyingFlee(
        to settings: CombatBehaviorSettings, interior: Bool
    ) -> CombatBehaviorSettings {
        var settings = settings
        let margin = max(0, settings.fleeBreakDistance - settings.fleeDistance)
        settings.fleeDistance = fleeDistance(interior: interior)
        settings.fleeBreakDistance = settings.fleeDistance + margin
        return settings
    }
}

/// Three radii a combat style picks between: `low` at a multiplier of 0, `mid` at the
/// neutral 0.5, and `high` at 1, blended in between.
nonisolated public struct CombatRadii: Equatable, Sendable {
    public var low: Float
    public var mid: Float
    public var high: Float

    public init(low: Float, mid: Float, high: Float) {
        self.low = low
        self.mid = mid
        self.high = high
    }

    /// The radius for a style multiplier, clamped to 0...1. Never negative.
    public func radius(at level: Float) -> Float {
        let level = level.isFinite ? min(max(level, 0), 1) : 0.5
        let (from, to, blend) = level < 0.5 ? (low, mid, level * 2) : (mid, high, level * 2 - 1)
        let radius = from + (to - from) * blend
        return radius.isFinite ? max(radius, 0) : 0
    }
}

nonisolated extension CombatAISettings {
    mutating func readRanges(store: GameSettingStore) {
        let ranges: [(String, WritableKeyPath<Self, Float>)] = [
            ("fCombatAdvanceInnerRadiusMin", \.advanceInnerRadius.low),
            ("fCombatAdvanceInnerRadiusMid", \.advanceInnerRadius.mid),
            ("fCombatAdvanceInnerRadiusMax", \.advanceInnerRadius.high),
            ("fCombatAdvanceOuterRadiusMin", \.advanceOuterRadius.low),
            ("fCombatAdvanceOuterRadiusMid", \.advanceOuterRadius.mid),
            ("fCombatAdvanceOuterRadiusMax", \.advanceOuterRadius.high),
            ("fCombatAbsoluteMaxRangeMult", \.absoluteMaxRangeMult),
            ("fCombatCurrentWeaponAbsoluteMaxRangeMult", \.currentWeaponAbsoluteMaxRangeMult),
            ("fAIUseWeaponDistance", \.useWeaponDistance),
            ("fAIShoutMinAimSeconds", \.shoutMinAimSeconds),
            ("fAIShoutToleranceDegrees", \.shoutToleranceDegrees),
            ("fAIShoutRetryDelaySeconds", \.shoutRetryDelaySeconds),
            ("fCombatOrbitDistance", \.orbitDistance),
            ("fCombatHoverTimeMin", \.hoverTimeMin),
            ("fCombatPerchAttackTimeMin", \.perchAttackTimeMin),
            ("fCombatGroundAttackTimeMin", \.groundAttackTimeMin),
            ("fCombatGroundAttackTimeMax", \.groundAttackTimeMax)
        ]
        for (editorID, keyPath) in ranges {
            store.read(editorID, into: &self, keyPath)
        }
        store.read("iAICombatRestoreHealthPercentage", into: &self, \.restoreHealthPercentage)
    }
}
