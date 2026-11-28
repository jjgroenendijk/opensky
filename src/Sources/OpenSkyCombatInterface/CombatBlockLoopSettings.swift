// The block loop of an actor with a combat style: block, block attack, and bashes, rolled
// about four times a second (docs/engine/combat-blocking.md). Only `fCombatBashReach` is a
// game setting in `Skyrim.esm`; the other numbers are the game's built-in values.

import Foundation

nonisolated public struct CombatBlockLoopSettings: Equatable, Sendable {
    /// `lerp(defensive, 0, 1)`, times the no-shield multiplier when the actor has no shield.
    public var blockChance: Float = 0.5
    /// `lerp(defensive, 0, 1)`.
    public var blockAttackChance: Float = 0.5
    /// `lerp(defensive, 0.025, 0.2)` and `lerp(offensive, 0, 0.05)`, each times the style's
    /// bash value.
    public var bashChance: Float = 0.1125
    public var offensiveBashChance: Float = 0.025
    /// What a bash chance is multiplied by for each state of the target.
    public var bashTargetMults = CombatBashTargetMults()
    /// `lerp(defensive, 32, 192)` and `lerp(defensive, 128, 384)`, before both radii and
    /// the target's reach are added.
    public var blockStartDistance: Float = 112
    public var blockStopDistance: Float = 256
    /// The three-point lerp of 4, 8, and 10,000 s at `2 * defensive - 1`.
    public var blockSeconds: Float = 8
    /// A block attack holds for a time drawn in this range.
    public var blockAttackSeconds = CombatSettingRange(1, 2)
    /// What the attack chance is multiplied by while the actor blocks: against a target that
    /// draws or swings, and against any other target, `lerp(defensive, 0.67, 0.2)`.
    public var attackChanceBlockingSwingMult: Float = 0
    public var attackChanceBlockingMult: Float = 0.435
    /// The wait between two passes, and between two bash rolls while a block holds.
    public var passSeconds: Float = 0.25
    /// How often a block checks the stop distance.
    public var stopCheckSeconds: Float = 1
    /// How far ahead the distance is predicted.
    public var predictSeconds: Float = 0.5
    /// No block starts while the target moves away faster than this, in units a second.
    public var targetRetreatSpeed: Float = 128
    /// The share of the target's strike angle that counts as an attack at the blocker.
    public var strikeAngleMult: Float = 1.25
    /// A block attack starts within both radii plus this share of the target's reach.
    public var blockAttackReachMult: Float = 1.5

    public init() {}

    /// The loop of a style with these `CSGD` offensive and defensive values.
    public init(offensive: Float, defensive: Float, bash: CombatBashTargetMults) {
        let defense = defensive.isFinite ? defensive : 0
        blockChance = CombatSettingRange(0, 1).lerp(defense)
        blockAttackChance = CombatSettingRange(0, 1).lerp(defense)
        bashChance = CombatSettingRange(0.025, 0.2).lerp(defense) * bash.bash
        offensiveBashChance = CombatSettingRange(0, 0.05).lerp(offensive) * bash.bash
        bashTargetMults = bash
        blockStartDistance = CombatSettingRange(32, 192).lerp(defense)
        blockStopDistance = CombatSettingRange(128, 384).lerp(defense)
        blockSeconds = Self.threePointLerp(4, 8, 10000, at: 2 * defense - 1)
        attackChanceBlockingMult = CombatSettingRange(0.67, 0.2).lerp(defense)
    }

    /// `min` at -1, `mid` at 0, and `max` at 1, held inside that range.
    public static func threePointLerp(_ low: Float, _ mid: Float, _ high: Float, at x: Float)
        -> Float
    {
        let x = min(max(x.isFinite ? x : 0, -1), 1)
        return x < 0 ? CombatSettingRange(low, mid).lerp(x + 1) : CombatSettingRange(mid, high)
            .lerp(x)
    }
}

/// The `CSME` bash values: the base multiplier, and the factor for a recoiling, a
/// power-attacking, an attacking, and a blocking target.
nonisolated public struct CombatBashTargetMults: Equatable, Sendable {
    public var bash: Float = 1
    public var recoil: Float = 1
    public var powerAttack: Float = 1
    public var attack: Float = 1
    /// For a target that blocks toward the actor within the 35 degree hit cone.
    public var blocking: Float = 0

    public init() {}
}
