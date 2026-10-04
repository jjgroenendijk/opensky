// How a CSTY combat style scales the combat machine's settings. No source says
// how vanilla turns a multiplier into behavior, so each mapping is OpenSky's:
// monotonic, clamped, and neutral at the vanilla default style.
// The table and its reasons: docs/engine/combat-behavior.md#combat-style.

import Foundation
import OpenSkyCombatInterface
import OpenSkyFormatsESM

/// The style numbers the machine reads, already defaulted, so a test can
/// write one without building a record.
nonisolated public struct CombatStyleTuning: Equatable, Sendable {
    /// The `CSGD` values of the vanilla default style, where every mapping is 1.
    public static let neutralOffense: Float = 0.5
    public static let neutralDefense: Float = 0.5
    /// The attack interval scale stays inside a half and double the base.
    public static let intervalScaleRange: ClosedRange<Float> = 0.5 ... 2
    /// A block or cast chance never reaches certainty, so the other choice stays possible.
    public static let chanceRange: ClosedRange<Float> = 0 ... 0.9

    public var offensiveMultiplier: Float
    public var defensiveMultiplier: Float
    public var meleeScoreMultiplier: Float
    public var magicScoreMultiplier: Float
    /// The style's editor ID, for the readout.
    public var name: String?

    /// The neutral style: every derived setting equals its base.
    public static let neutral = CombatStyleTuning(
        offensiveMultiplier: neutralOffense,
        defensiveMultiplier: neutralDefense,
        meleeScoreMultiplier: 1,
        magicScoreMultiplier: 1
    )

    public init(
        offensiveMultiplier: Float,
        defensiveMultiplier: Float,
        meleeScoreMultiplier: Float,
        magicScoreMultiplier: Float,
        name: String? = nil
    ) {
        self.offensiveMultiplier = offensiveMultiplier
        self.defensiveMultiplier = defensiveMultiplier
        self.meleeScoreMultiplier = meleeScoreMultiplier
        self.magicScoreMultiplier = magicScoreMultiplier
        self.name = name
    }

    /// The members a record leaves out keep the neutral value.
    public init(style: CombatStyle) {
        let neutral = Self.neutral
        self.init(
            offensiveMultiplier: style.value(.offensiveMultiplier) ?? neutral.offensiveMultiplier,
            defensiveMultiplier: style.value(.defensiveMultiplier) ?? neutral.defensiveMultiplier,
            meleeScoreMultiplier: style.value(.meleeScoreMultiplier)
                ?? neutral.meleeScoreMultiplier,
            magicScoreMultiplier: style.value(.magicScoreMultiplier)
                ?? neutral.magicScoreMultiplier,
            name: style.editorID
        )
    }

    /// The attack interval divides by offense over neutral: twice the offense,
    /// half the wait. The block time follows it, so a block still replaces one gap.
    public func attackIntervalScale() -> Float {
        let offense = Self.finitePositive(offensiveMultiplier, or: Self.neutralOffense)
        return Self.clamp(Self.neutralOffense / offense, to: Self.intervalScaleRange)
    }

    /// The block chance scales with defense over neutral.
    public func blockChance(base: Float) -> Float {
        let defense = Self.finitePositive(defensiveMultiplier, or: Self.neutralDefense)
        return Self.clamp(base * defense / Self.neutralDefense, to: Self.chanceRange)
    }

    /// The cast chance scales with the magic share of the two equipment scores.
    /// Equal scores give the base.
    public func castChance(base: Float) -> Float {
        let magic = Self.finiteNonNegative(magicScoreMultiplier)
        let melee = Self.finiteNonNegative(meleeScoreMultiplier)
        guard magic + melee > 0 else { return base }
        return Self.clamp(base * 2 * magic / (magic + melee), to: Self.chanceRange)
    }

    private static func finitePositive(_ value: Float, or fallback: Float) -> Float {
        value.isFinite && value > 0 ? value : fallback
    }

    private static func finiteNonNegative(_ value: Float) -> Float {
        value.isFinite ? max(0, value) : 0
    }

    private static func clamp(_ value: Float, to range: ClosedRange<Float>) -> Float {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

nonisolated extension CombatBehaviorSettings {
    /// These settings scaled by `tuning`. A nil tuning returns them unchanged.
    public func tuned(by tuning: CombatStyleTuning?) -> CombatBehaviorSettings {
        guard let tuning else { return self }
        var settings = self
        let scale = tuning.attackIntervalScale()
        settings.attackIntervalSeconds = attackIntervalSeconds * scale
        settings.blockSeconds = blockSeconds * scale
        settings.blockChance = tuning.blockChance(base: blockChance)
        settings.castChance = tuning.castChance(base: castChance)
        return settings
    }
}
