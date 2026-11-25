// The damage and armour the item card and the barter bar show: the player's own
// values after skill and perks, from UESP "Skyrim:Weapons" and "Skyrim:Armor".
// See docs/engine/barter.md#the-item-card.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyProgressionInterface

extension CombatCoordinator {
    /// `round((base + tempering) × skill factor × perks)` for the player holding `item`.
    public func shownDamage(of item: FormID, temperLevel: Int32) -> Int? {
        ShownStatRules(owner: self).shownDamage(of: item, temperLevel: temperLevel)
    }

    /// `ceiling((base + tempering) × skill factor)`, then the player's
    /// `Mod Armor Rating` perks, for the player wearing `item`.
    public func shownArmourRating(of item: FormID, temperLevel: Int32) -> Float? {
        ShownStatRules(owner: self).shownArmourRating(of: item, temperLevel: temperLevel)
    }

    /// The player's `Damage Resist`, which armour spells such as Oakflesh raise. The bar
    /// adds it to the worn pieces.
    public var shownArmourBonus: Float {
        let bonus = playerValue(named: "Damage Resist")
        return bonus.isFinite ? bonus : 0
    }

    private func playerValue(named name: String) -> Float {
        ShownStatRules(owner: self).playerValue(named: name)
    }
}

extension CombatCoordinator {
    /// Works out the damage and armour rating the menus show.
    struct ShownStatRules {
        let owner: CombatCoordinator

        func shownDamage(of item: FormID, temperLevel: Int32) -> Int? {
            let shared = owner.shared
            guard let weapon = shared.items?.weapon(item) else { return nil }
            let profile = MeleeWeaponProfile(weapon: weapon).tempered(level: temperLevel)
            let subjects = PerkEvaluationSubjects(owner: .player)
                .binding(.weapon, to: shared.items?.conditionSubject(of: item))
            let perks = shared.perks
            var damage = perks.perkValue(
                profile.damage, at: .calculateWeaponDamage, on: .player, subjects: subjects
            )
            let values = shared.world.actorValues(of: .player)
            if
                let index = SkillUseAction.weaponHit(profile.handType).skillIndex,
                let skill = values?(index)
            {
                damage *= WeaponStrikeRules.playerSkillMultiplier(
                    skill: skill, settings: shared.weaponDamage
                )
            }
            damage *= perks.perkValue(1, at: .modAttackDamage, on: .player, subjects: subjects)
            damage *= values?(ActorValueIndex.attackDamageMult) ?? 1
            return damage.isFinite ? Int(max(0, damage).rounded()) : nil
        }

        func shownArmourRating(of item: FormID, temperLevel: Int32) -> Float? {
            let shared = owner.shared
            guard
                let armor = shared.items?.armor[item.rawValue],
                let type = armor.bodyTemplate?.armorType
            else { return nil }
            let isBody = armor.bodyTemplate?.slots.contains(.body) ?? false
            let tempered = Float(armor.armorRating & 0xFFFF) / 100
                + Tempering.bonus(level: temperLevel, isBodyArmor: isBody)
            let scaled = WeaponStrikeRules.armorRating(
                pieces: [WornArmorPiece(rating: tempered, type: type)],
                skills: playerArmourSkills(),
                isPlayer: true,
                settings: shared.weaponDamage
            )
            let subjects = PerkEvaluationSubjects(owner: .player)
                .binding(.item, to: shared.items?.conditionSubject(of: item))
            let rating = shared.perks.perkValue(
                scaled.rounded(.up), at: .modArmorRating, on: .player, subjects: subjects
            )
            return rating.isFinite ? max(0, rating) : nil
        }

        func playerArmourSkills() -> ArmorSkills {
            ArmorSkills(
                light: owner.playerValue(named: "Light Armor"),
                heavy: owner.playerValue(named: "Heavy Armor")
            )
        }

        func playerValue(named name: String) -> Float {
            let shared = owner.shared
            let values = shared.world.actorValues(of: .player)
            return ActorValueIdentity.index(named: name).flatMap { values?($0) } ?? 0
        }
    }
}
