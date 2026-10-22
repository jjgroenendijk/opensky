// How hard a hit staggers, the chance it does, and the disarm perk chances, from the
// `fStagger*`, `iStaggerAttackChance`, and `iPerk*DisarmChance` settings. No source
// says how the game combines the stagger settings, so each use is OpenSky's reading
// (docs/engine/melee-combat.md#stagger).

import Foundation
import OpenSkyGameData

nonisolated public struct StaggerSettings: Equatable, Sendable {
    /// `fStaggerMin`: a magnitude at or below it does not stagger.
    public var minimum: Float = 0
    /// `fStaggerMassOffsetBase` and `fStaggerPlayerMassMult`: the player counts as this
    /// much heavier, and a heavier target staggers less.
    public var massOffsetBase: Float = 2.1
    public var playerMassMult: Float = 2.5
    /// `fStaggerBlockBase` and `fStaggerBlockMult`: the recoil a blocked swing puts on its
    /// attacker, per point of the blocker's Block skill.
    public var blockBase: Float = 0.001
    public var blockMult: Float = 0.005
    /// `fStaggerBlockingMult`: what a blocked hit that is not a power attack keeps.
    public var blockingMult: Float = 0
    /// `fStaggerBlockAttackMult`: a weapon bash scales its stagger by `1 + mult * Block`.
    public var blockAttackMult: Float = -0.0001
    /// `fStaggerBlockAttackShieldBase` and `...ShieldMult`: a shield bash's stagger, per
    /// point of the shield's armour rating.
    public var blockAttackShieldBase: Float = 0.01
    public var blockAttackShieldMult: Float = 0.001
    /// `iStaggerAttackChance`: percent chance that a hit with a magnitude staggers.
    public var attackChance = 50
    /// `iPerkAttackDisarmChance` and `iPerkBlockDisarmChance`: percent chance that a
    /// disarm spell of `Apply Combat Hit Spell` or `Apply Bashing Spell` takes the weapon.
    public var attackDisarmChance = 50
    public var blockDisarmChance = 50

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fStaggerMin", into: &settings, \.minimum)
        store.read("fStaggerMassOffsetBase", into: &settings, \.massOffsetBase)
        store.read("fStaggerPlayerMassMult", into: &settings, \.playerMassMult)
        store.read("fStaggerBlockBase", into: &settings, \.blockBase)
        store.read("fStaggerBlockMult", into: &settings, \.blockMult)
        store.read("fStaggerBlockingMult", into: &settings, \.blockingMult)
        store.read("fStaggerBlockAttackMult", into: &settings, \.blockAttackMult)
        store.read("fStaggerBlockAttackShieldBase", into: &settings, \.blockAttackShieldBase)
        store.read("fStaggerBlockAttackShieldMult", into: &settings, \.blockAttackShieldMult)
        store.read("iStaggerAttackChance", into: &settings, \.attackChance)
        store.read("iPerkAttackDisarmChance", into: &settings, \.attackDisarmChance)
        store.read("iPerkBlockDisarmChance", into: &settings, \.blockDisarmChance)
        return settings
    }
}

/// One hit, as the stagger magnitude reads it.
nonisolated public struct StaggerHit: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case swing
        case power
        /// A bash with a weapon, or with a shield of this armour rating.
        case bash(shieldRating: Float?)
    }

    /// WEAP DNAM `stagger`.
    public var weaponStagger: Float
    /// `Mod Target Stagger` times `Mod Incoming Stagger`.
    public var perkMultiplier: Float = 1
    public var kind = Kind.swing
    /// A power bash breaks a block as a power attack does.
    public var isPowerBash = false
    public var wasBlocked = false
    public var isPlayerTarget = false
    /// The attacker's Block skill, which a weapon bash reads.
    public var attackerBlockSkill: Float = 0

    public init(weaponStagger: Float) {
        self.weaponStagger = weaponStagger
    }
}

nonisolated public enum StaggerRule {
    /// The magnitude written to `staggerMagnitude` before `staggerStart`.
    public static func magnitude(_ hit: StaggerHit, settings: StaggerSettings) -> Float {
        var magnitude: Float = switch hit.kind {
        case .swing, .power:
            hit.weaponStagger
        case let .bash(shieldRating?):
            settings.blockAttackShieldBase
                + settings.blockAttackShieldMult * finite(shieldRating)
        case .bash(nil):
            hit.weaponStagger
                * max(0, 1 + settings.blockAttackMult * finite(hit.attackerBlockSkill))
        }
        magnitude *= finite(hit.perkMultiplier)
        let breaksBlock = hit.kind == .power || hit.isPowerBash
        if hit.wasBlocked, !breaksBlock {
            magnitude *= max(0, settings.blockingMult)
        }
        let mass = hit.isPlayerTarget ? max(1, settings.playerMassMult) : 1
        let base = max(0, settings.massOffsetBase)
        if base + mass - 1 > 0 {
            magnitude *= base / (base + mass - 1)
        }
        return finite(magnitude)
    }

    /// The recoil a blocked swing puts on its attacker.
    public static func blockRecoil(blockerSkill: Float, settings: StaggerSettings) -> Float {
        finite(settings.blockBase + settings.blockMult * finite(blockerSkill))
    }

    /// Whether a hit of `magnitude` staggers, for a percent `roll` in 0..<100.
    public static func staggers(magnitude: Float, roll: Int, settings: StaggerSettings) -> Bool {
        magnitude > settings.minimum && roll < settings.attackChance
    }

    private static func finite(_ value: Float) -> Float {
        value.isFinite ? max(0, value) : 0
    }
}
