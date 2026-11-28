// The close-range moves of a melee actor in reach: back off, circle, and fall back.
// The chances and distances come from the combat style's CSCR values and the game's
// circle and fallback settings (docs/formats/combat-style.md#close-range-movement).

import Foundation

nonisolated public struct CombatCloseRangeSettings: Equatable, Sendable {
    /// `lerp(circle, fCombatCircleChanceMin, fCombatCircleChanceMax)`.
    public var circleChance: Float = 0.15
    /// `lerp(fallback, fCombatFallbackChanceMin, fCombatFallbackChanceMax)`.
    public var fallbackChance: Float = 0.1
    /// `lerp(fallback, fCombatFallbackDistanceMin, fCombatFallbackDistanceMax)`, in units.
    public var fallbackDistance: Float = 128
    /// `lerp(fallback, fCombatFallbackWaitTimeMin, fCombatFallbackWaitTimeMax)`, in seconds.
    public var fallbackWaitSeconds: Float = 0.9
    /// The circle angle is drawn between `circleAngleMin` and `circleAngleMax`, in degrees.
    /// `circleAngleMax` is the style's lerp; `circleAngleCap` is `fCombatCircleAngleMax`.
    public var circleAngleMin: Float = 30
    public var circleAngleMax: Float = 42
    public var circleAngleCap: Float = 90
    /// `fCombatCircleAnglePlayerMult`: the circle angle against the player.
    public var circleAnglePlayerMult: Float = 0.75
    /// `fCombatCircleMinDistanceRadiusMult`: the least circle arc, in actor radii.
    public var circleMinDistanceRadiusMult: Float = 3
    /// The chance to back off when no circle or fallback starts.
    public var backOffChance: Float = 0.25
    /// The wait after a pass that started no move.
    public var pauseSeconds: Float = 0.25
    /// The wait after a fallback cancelled before it ended.
    public var cancelledFallbackWaitSeconds: Float = 0.75
    /// How often a running move is checked, and when a fallback is first checked.
    public var checkSeconds: Float = 0.1
    public var fallbackFirstCheckSeconds: Float = 0.5
    /// A move starts only while the actor faces the target within this angle, in degrees.
    public var startFacingDegrees: Float = 30
    /// A fallback starts only while the target faces the actor within this angle.
    public var fallbackTargetFacingDegrees: Float = 60
    /// A circle side fails when its point lies further off the target's facing.
    public var circleTargetFacingDegrees: Float = 75
    /// A circle ends early when the target's distance half a second ahead passes this,
    /// and a fallback is cancelled past `fallbackBreakDistance`.
    public var circleBreakDistance: Float = 1024
    public var fallbackBreakDistance: Float = 256

    public init() {}
}

/// A pair of game settings a style value lerps between: `min` at 0, `max` at 1.
nonisolated public struct CombatSettingRange: Equatable, Sendable {
    public var min: Float
    public var max: Float

    public init(_ min: Float, _ max: Float) {
        self.min = min
        self.max = max
    }

    /// The game's lerp, with a value that is not finite read as 0.
    public func lerp(_ value: Float) -> Float {
        min + (max - min) * (value.isFinite ? value : 0)
    }
}

/// The game settings the close-range values lerp between, read from `GMST`.
nonisolated public struct CombatCloseRangeRanges: Equatable, Sendable {
    public var circleChance = CombatSettingRange(0, 0.75)
    public var fallbackChance = CombatSettingRange(0, 0.5)
    public var fallbackDistance = CombatSettingRange(96, 256)
    public var fallbackWaitSeconds = CombatSettingRange(0.75, 1.5)
    public var circleAngle = CombatSettingRange(30, 90)
    public var circleAnglePlayerMult: Float = 0.75
    public var circleMinDistanceRadiusMult: Float = 3

    public init() {}

    /// The close-range settings of a style with these `CSCR` circle and fallback values.
    public func settings(circle: Float, fallback: Float) -> CombatCloseRangeSettings {
        var settings = CombatCloseRangeSettings()
        settings.circleChance = circleChance.lerp(circle)
        settings.fallbackChance = fallbackChance.lerp(fallback)
        settings.fallbackDistance = fallbackDistance.lerp(fallback)
        settings.fallbackWaitSeconds = fallbackWaitSeconds.lerp(fallback)
        settings.circleAngleMin = circleAngle.min
        settings.circleAngleMax = circleAngle.lerp(circle)
        settings.circleAngleCap = circleAngle.max
        settings.circleAnglePlayerMult = circleAnglePlayerMult
        settings.circleMinDistanceRadiusMult = circleMinDistanceRadiusMult
        return settings
    }
}
