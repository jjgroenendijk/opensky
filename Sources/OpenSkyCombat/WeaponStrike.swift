// The terms a weapon hit is scaled by beyond its base damage and the block:
// the attacker's weapon skill, a sneak attack, and the target's worn armour.
// Sources and the order of the terms: docs/engine/melee-damage.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM

/// The scale terms of one hit. `plain` changes nothing.
nonisolated public struct WeaponStrike: Equatable, Sendable {
    public var skillMultiplier: Float
    /// 1 unless the target did not detect the attacker.
    public var sneakMultiplier: Float
    /// The fraction of damage the target's armour stops, after the cap.
    public var armorFraction: Float
    /// `1 + fPowerAttackDefaultBonus` for a power attack.
    public var powerMultiplier: Float = 1

    public static let plain = Self()

    public init(
        skillMultiplier: Float = 1,
        sneakMultiplier: Float = 1,
        armorFraction: Float = 0
    ) {
        self.skillMultiplier = skillMultiplier
        self.sneakMultiplier = sneakMultiplier
        self.armorFraction = armorFraction
    }

    public var isSneakAttack: Bool {
        sneakMultiplier != 1
    }

    /// Every term as one factor on the damage.
    public var factor: Float {
        let terms = [skillMultiplier, sneakMultiplier, 1 - armorFraction, powerMultiplier]
        return terms.reduce(1) { $0 * ($1.isFinite ? max(0, $1) : 1) }
    }
}

/// One worn piece, with its tempering already added to the rating.
nonisolated public struct WornArmorPiece: Equatable, Sendable {
    public let rating: Float
    public let type: ArmorType

    public init(rating: Float, type: ArmorType) {
        self.rating = rating
        self.type = type
    }
}

/// The armour skills of the wearer, 0 through 100.
nonisolated public struct ArmorSkills: Equatable, Sendable {
    public var light: Float
    public var heavy: Float

    public init(light: Float, heavy: Float) {
        self.light = light
        self.heavy = heavy
    }
}

nonisolated public enum WeaponStrikeRules: Sendable {
    /// The player's damage factor for `skill`: 1 at 0, `fDamagePCSkillMax` at 100.
    public static func playerSkillMultiplier(
        skill: Float,
        settings: WeaponDamageSettings
    ) -> Float {
        1 + (settings.playerSkillMax - 1) * clampedSkill(skill) / 100
    }

    /// The sneak-attack factor of a weapon family, before perks. A bow has no
    /// setting and stays at 2 (UESP "Skyrim:Sneak").
    public static func sneakMultiplier(
        handType: CombatHandType, settings: WeaponDamageSettings
    ) -> Float {
        let family: Float = switch handType {
        case .sword: settings.sneakOneHandedSword
        case .axe: settings.sneakOneHandedAxe
        case .mace: settings.sneakOneHandedMace
        case .dagger: settings.sneakDagger
        case .greatsword: settings.sneakTwoHandedSword
        case .battleaxe: settings.sneakTwoHandedAxe
        case .handToHand: settings.sneakHand
        case .bow, .crossbow: 2
        default: 1
        }
        return family * settings.sneakAttackMult * settings.sneakAttackBonusPercent / 100
    }

    /// The summed rating of the worn pieces, each scaled by its armour skill.
    /// `extra` is the `Damage Resist` actor value, which spells such as Oakflesh raise.
    public static func armorRating(
        pieces: [WornArmorPiece],
        skills: ArmorSkills,
        isPlayer: Bool,
        extra: Float = 0,
        settings: WeaponDamageSettings
    ) -> Float {
        let top = isPlayer ? settings.armorRatingPlayerMax : settings.armorRatingMax
        let worn = pieces.reduce(Float(0)) { total, piece in
            let rating = piece.rating.isFinite ? max(0, piece.rating) : 0
            let factor: Float = switch piece.type {
            case .light:
                settings.armorRatingBase
                    + (top - settings.armorRatingBase) * clampedSkill(skills.light) / 100
            case .heavy:
                settings.armorRatingBase
                    + (top - settings.armorRatingBase) * clampedSkill(skills.heavy) / 100
            case .clothing:
                settings.clothingArmorScale
            }
            return total + rating * factor
        }
        return worn + (extra.isFinite ? extra : 0)
    }

    /// The stopped fraction: rating times `fArmorScalingFactor` percent, plus
    /// `fArmorBaseFactor` per light or heavy piece, capped at `fMaxArmorRating`.
    public static func armorFraction(
        rating: Float, pieces: [WornArmorPiece], settings: WeaponDamageSettings
    ) -> Float {
        let armored = pieces.count { $0.type != .clothing }
        let raw = max(0, rating) * settings.armorScalingFactor / 100
            + Float(armored) * settings.armorBaseFactor
        let cap = max(0, settings.maxArmorRating) / 100
        guard raw.isFinite else { return 0 }
        return min(max(raw, 0), cap)
    }

    private static func clampedSkill(_ skill: Float) -> Float {
        skill.isFinite ? min(max(skill, 0), 100) : 0
    }
}
