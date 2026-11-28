// How a CSTY combat style scales the combat machine's settings. No source says
// how vanilla turns a multiplier into behavior, so each mapping is OpenSky's:
// monotonic, clamped, and neutral at the vanilla default style.
// The table and its reasons: docs/engine/combat-behavior.md#combat-style.

import Foundation
public import OpenSkyCombatInterface
public import OpenSkyFormatsESM

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
    /// `CSFL` hover, ground attack, and perch attack times, and the perch chance, 0 to 1.
    /// UESP gives 0.5 as the default of each.
    public var flight = FlightStyle()
    /// `CSGD` Avoid Threat Chance, 0 to 1: the chance to sidestep a danger.
    public var avoidThreatChance: Float = 0.2
    /// The `CSME` multipliers the attack pick weighs by.
    public var attackWeights = NPCAttackWeights()
    /// `CSCR` circle and fallback multipliers, 0 to 1.
    public var circleMultiplier: Float = 0.2
    public var fallbackMultiplier: Float = 0.2
    /// `CSLR`, the strafe multiplier, 0 to 1.
    public var strafeMultiplier: Float = 0.2
    /// `CSCR` flank distance and stalk time, 0 to 1, and `DATA` flag 0x02.
    public var flankDistance: Float = 0.2
    public var stalkTime: Float = 0.2
    public var flanks = false
    /// The `CSME` bash values.
    public var bash = CombatBashTargetMults()
    /// The style's editor ID, for the readout.
    public var name: String?

    nonisolated public struct FlightStyle: Equatable, Sendable {
        public var hoverTime: Float = 0.5
        public var groundAttackTime: Float = 0.5
        public var perchAttackChance: Float = 0.5
        public var perchAttackTime: Float = 0.5

        public init() {}
    }

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
        avoidThreatChance = style.value(.avoidThreatChance) ?? avoidThreatChance
        attackWeights = NPCAttackWeights(style: style)
        circleMultiplier = style.value(.circleMultiplier) ?? circleMultiplier
        fallbackMultiplier = style.value(.fallbackMultiplier) ?? fallbackMultiplier
        strafeMultiplier = style.strafeMultiplier ?? strafeMultiplier
        flankDistance = style.value(.flankDistance) ?? flankDistance
        stalkTime = style.value(.stalkTime) ?? stalkTime
        flanks = (style.flags ?? 0) & 0x02 != 0
        bash.bash = style.value(.bashMultiplier) ?? bash.bash
        bash.recoil = style.value(.bashRecoilMultiplier) ?? bash.recoil
        bash.attack = style.value(.bashAttackMultiplier) ?? bash.attack
        bash.powerAttack = style.value(.bashPowerAttackMultiplier) ?? bash.powerAttack
        flight.hoverTime = style.value(.hoverTime) ?? flight.hoverTime
        flight.groundAttackTime = style.value(.groundAttackTime) ?? flight.groundAttackTime
        flight.perchAttackChance = style.value(.perchAttackChance) ?? flight.perchAttackChance
        flight.perchAttackTime = style.value(.perchAttackTime) ?? flight.perchAttackTime
    }

    /// The attack interval divides by offense over neutral: twice the offense,
    /// half the wait. The block time follows it, so a block still replaces one gap.
    public func attackIntervalScale() -> Float {
        let offense = Self.finitePositive(offensiveMultiplier, or: Self.neutralOffense)
        return Self.clamp(Self.neutralOffense / offense, to: Self.intervalScaleRange)
    }

    /// The attack chance at the offensive value: `fCombatAttackChanceMin` (0.05) to
    /// `fCombatAttackChanceMax` (1).
    public func attackChance() -> Float {
        let offense = offensiveMultiplier.isFinite ? offensiveMultiplier : Self.neutralOffense
        return Self.attackChanceMin + (Self.attackChanceMax - Self.attackChanceMin) * offense
    }

    public static let attackChanceMin: Float = 0.05
    public static let attackChanceMax: Float = 1

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

    /// The out-of-reach cast chance: 1 unless the melee score outweighs the magic
    /// score, then the magic share of the two, doubled.
    public func rangedCastChance() -> Float {
        let magic = Self.finiteNonNegative(magicScoreMultiplier)
        let melee = Self.finiteNonNegative(meleeScoreMultiplier)
        guard magic + melee > 0 else { return 1 }
        return Self.clamp(2 * magic / (magic + melee), to: 0 ... 1)
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
        settings.rangedCastChance = min(rangedCastChance, tuning.rangedCastChance())
        settings.attackChance = tuning.attackChance()
        settings.staggeredAttackMult = max(
            tuning.attackWeights.attackStaggered, tuning.attackWeights.powerAttackStaggered
        )
        settings.closeRange = CombatCloseRangeRanges().settings(
            circle: tuning.circleMultiplier, fallback: tuning.fallbackMultiplier
        )
        settings.blockLoop = CombatBlockLoopSettings(
            offensive: tuning.offensiveMultiplier, defensive: tuning.defensiveMultiplier,
            bash: tuning.bash
        )
        settings.movement = CombatMovementSettings(circle: tuning.circleMultiplier)
        settings.strafe = CombatStrafeSettings(strafe: tuning.strafeMultiplier)
        settings.flank = tuning.flanks ? CombatFlankSettings(
            stalkTime: tuning.stalkTime, flankDistance: tuning.flankDistance
        ) : nil
        return settings
    }
}
