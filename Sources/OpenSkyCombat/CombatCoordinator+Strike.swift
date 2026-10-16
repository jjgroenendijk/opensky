// The skill, sneak-attack, and armour terms of one weapon hit, read from the
// world. The arithmetic lives in `WeaponStrikeRules`. Perks that change these
// terms need the weapon and armour condition tabs, which are not bound yet.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyProgressionInterface

extension CombatCoordinator {
    /// The terms of a hit by `attacker` with `handType` on `target`.
    public func strike(
        from attacker: ReferenceKey, handType: CombatHandType, on target: ReferenceKey
    ) -> WeaponStrike {
        guard let world else { return .plain }
        var strike = WeaponStrike()
        if
            attacker == .player,
            let index = SkillUseAction.weaponHit(handType).skillIndex,
            let skill = world.actorValues(of: .player)?(index)
        {
            strike.skillMultiplier = WeaponStrikeRules.playerSkillMultiplier(
                skill: skill, settings: weaponDamage
            )
        }
        if isSneakAttack(by: attacker, on: target) {
            strike.sneakMultiplier = WeaponStrikeRules.sneakMultiplier(
                handType: handType, settings: weaponDamage
            )
        }
        strike.armorFraction = armorFraction(of: target)
        return strike
    }

    /// Only the player sneak attacks: the player has no detection state toward an
    /// NPC. A target already fighting the player knows where the player is.
    func isSneakAttack(by attacker: ReferenceKey, on target: ReferenceKey) -> Bool {
        guard attacker == .player, target != .player, let world else { return false }
        if let loop, loop.activity(of: target) != .notFighting {
            return false
        }
        return !world.awareness(of: target, toward: attacker).isDetected
    }

    /// The fraction of a blow `target`'s worn armour stops.
    public func armorFraction(of target: ReferenceKey) -> Float {
        guard let world, let items else { return 0 }
        let pieces = world.equippedItems(of: target).compactMap { worn -> WornArmorPiece? in
            guard
                let armor = items.armor[worn.item.rawValue],
                let type = armor.bodyTemplate?.armorType
            else { return nil }
            let isBody = armor.bodyTemplate?.slots.contains(.body) ?? false
            let rating = Float(armor.armorRating & 0xFFFF) / 100
                + Tempering.bonus(level: worn.temperLevel, isBodyArmor: isBody)
            return WornArmorPiece(rating: rating, type: type)
        }
        let values = world.actorValues(of: target)
        let read = { (name: String) -> Float in
            ActorValueIdentity.index(named: name).flatMap { values?($0) } ?? 0
        }
        let rating = WeaponStrikeRules.armorRating(
            pieces: pieces,
            skills: ArmorSkills(light: read("Light Armor"), heavy: read("Heavy Armor")),
            isPlayer: target == .player,
            extra: read("Damage Resist"),
            settings: weaponDamage
        )
        return WeaponStrikeRules.armorFraction(
            rating: rating,
            pieces: pieces,
            settings: weaponDamage
        )
    }
}
