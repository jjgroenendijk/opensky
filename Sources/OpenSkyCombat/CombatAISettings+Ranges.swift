// How the game's advance, range, healing, shout, and flight settings reach one actor's
// combat machine. No source says how the game applies them, so each mapping is OpenSky's
// reading (docs/engine/combat-behavior.md#game-settings).

import Foundation
import OpenSkyCombatInterface

nonisolated extension CombatAISettings {
    /// `settings` with these values. The style's offense picks the walk radius (more
    /// offense, a smaller radius) and its defense the back-off radius.
    public func applyingRanges(
        to settings: CombatBehaviorSettings, tuning: CombatStyleTuning?
    ) -> CombatBehaviorSettings {
        let style = tuning ?? .neutral
        var settings = settings
        settings.walkRadius = advanceOuterRadius.radius(at: 1 - style.offensiveMultiplier)
        settings.backOffRadius = advanceInnerRadius.radius(at: style.defensiveMultiplier)
        settings.weaponRangeHoldMult = Self.atLeastOne(currentWeaponAbsoluteMaxRangeMult)
        settings.weaponAbsoluteRangeMult = Self.atLeastOne(absoluteMaxRangeMult)
        settings.spellRangeCap = useWeaponDistance.isFinite ? max(0, useWeaponDistance) : .infinity
        settings.restoreHealthFraction = min(max(Float(restoreHealthPercentage) / 100, 0), 1)
        settings.shoutAimSeconds = Self.nonNegative(shoutMinAimSeconds)
        settings.shoutToleranceRadians = Self.nonNegative(shoutToleranceDegrees) * .pi / 180
        settings.shoutRetrySeconds = Self.nonNegative(shoutRetryDelaySeconds)
        settings.flight = flight(style: style.flight)
        return settings
    }

    /// Ground time lies between the two ground settings by the style's ground attack
    /// time. Air and perch times scale their minimum by the style time over its 0.5
    /// default, never below the minimum.
    public func flight(style: CombatStyleTuning.FlightStyle) -> CombatFlightSettings {
        var flight = CombatFlightSettings()
        flight.orbitDistance = Self.nonNegative(orbitDistance)
        let blend = min(max(Self.nonNegative(style.groundAttackTime), 0), 1)
        let low = Self.nonNegative(groundAttackTimeMin)
        let high = max(low, Self.nonNegative(groundAttackTimeMax))
        flight.groundSeconds = low + (high - low) * blend
        flight.airSeconds = Self.scaled(hoverTimeMin, by: style.hoverTime)
        flight.perchSeconds = Self.scaled(perchAttackTimeMin, by: style.perchAttackTime)
        flight.perchChance = min(max(Self.nonNegative(style.perchAttackChance), 0), 1)
        return flight
    }

    private static func scaled(_ minimum: Float, by styleTime: Float) -> Float {
        let base = nonNegative(minimum)
        return max(base, base * nonNegative(styleTime) * 2)
    }

    private static func atLeastOne(_ value: Float) -> Float {
        value.isFinite ? max(1, value) : 1
    }

    private static func nonNegative(_ value: Float) -> Float {
        value.isFinite ? max(0, value) : 0
    }
}
