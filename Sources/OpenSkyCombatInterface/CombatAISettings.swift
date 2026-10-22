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
