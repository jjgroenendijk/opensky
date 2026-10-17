// The skill, sneak-attack, and armour terms of one weapon hit, read from the
// world. The arithmetic lives in `WeaponStrikeRules`; the perk terms are in
// `CombatCoordinator+Perks.swift`.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyProgressionInterface

extension CombatCoordinator {
    /// The terms of `blow` on `target`, perks of both sides included.
    public func strike(_ blow: CombatBlow, on target: ReferenceKey) -> WeaponStrike {
        guard let world else { return .plain }
        var strike = WeaponStrike()
        let attack = attackSubjects(blow, on: target)
        if
            blow.attacker == .player,
            let index = SkillUseAction.weaponHit(blow.handType).skillIndex,
            let skill = world.actorValues(of: .player)?(index)
        {
            strike.skillMultiplier = WeaponStrikeRules.playerSkillMultiplier(
                skill: skill, settings: weaponDamage
            )
        }
        if isSneakAttack(by: blow.attacker, on: target) {
            let family = WeaponStrikeRules.sneakMultiplier(
                handType: blow.handType, settings: weaponDamage
            )
            strike.sneakMultiplier = perkValue(
                family, at: .modSneakAttackMult, on: blow.attacker, subjects: attack
            )
        }
        strike.armorFraction = armorFraction(of: target, against: blow)
        applyPerkTerms(to: &strike, blow: blow, on: target)
        return strike
    }

    /// A sneak attack the player landed: Sneak experience and the HUD notice.
    func reportSneakAttack(_ strike: WeaponStrike, ranged: Bool) {
        guard strike.isSneakAttack else { return }
        let amount = ranged ? weaponDamage.sneakSkillUseRanged : weaponDamage.sneakSkillUseMelee
        _ = reportSkillUse(SkillUseEvent(actor: .player, action: .sneakAttack, amount: amount))
        world?.showNotification(weaponDamage.sneakNotice(multiplier: strike.sneakMultiplier))
    }

    /// The blow before the block, so a stronger hit costs more to stop.
    public func applyBlockStamina(_ damage: MeleeDamageResult, to blocker: ReferenceKey) {
        let incoming = damage.strike.damage(base: damage.base, attack: damage.attackMultiplier)
        world?.damageStamina(by: stamina.blockCost(incomingDamage: incoming), of: blocker)
    }

    /// UESP "Skyrim:Combat": a power attack needs at least one point of stamina.
    public func payMeleeStamina(_ cost: Float) -> Bool {
        guard let world else { return true }
        guard
            let index = ActorValueIdentity.index(named: "Stamina"),
            let stamina = world.actorValues(of: .player)?(index)
        else { return true }
        guard stamina >= 1 else { return false }
        world.damageStamina(by: cost, of: .player)
        return true
    }

    public func canPowerBash() -> Bool {
        world?.ownsPerk(editorID: "PowerBash", on: .player) ?? false
    }

    /// UESP "Skyrim:Block": a shield bash uses the shield's base rating, without tempering.
    public func meleeBashSource() -> (blockSkill: Float, shieldRating: Float?) {
        guard let world else { return (MeleeDamage.defaultBlockSkill, nil) }
        let skill = ActorValueIdentity.index(named: "Block")
            .flatMap { world.actorValues(of: .player)?($0) } ?? MeleeDamage.defaultBlockSkill
        let shield = world.equippedItems(of: .player).lazy.compactMap { worn -> Float? in
            guard
                let armor = self.items?.armor[worn.item.rawValue],
                armor.bodyTemplate?.slots.contains(.shield) ?? false
            else { return nil }
            return Float(armor.armorRating & 0xFFFF) / 100
        }.first
        return (skill, shield)
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

    /// The fraction of a blow `target`'s worn armour stops. Each piece passes the
    /// wearer's `Mod Armor Rating`, and the sum the attacker's `Mod Target Damage Resistance`.
    public func armorFraction(of target: ReferenceKey, against blow: CombatBlow? = nil) -> Float {
        guard let world, let items else { return 0 }
        let pieces = world.equippedItems(of: target).compactMap { worn -> WornArmorPiece? in
            guard
                let armor = items.armor[worn.item.rawValue],
                let type = armor.bodyTemplate?.armorType
            else { return nil }
            let isBody = armor.bodyTemplate?.slots.contains(.body) ?? false
            let tempered = Float(armor.armorRating & 0xFFFF) / 100
                + Tempering.bonus(level: worn.temperLevel, isBodyArmor: isBody)
            let rating = perkValue(
                tempered,
                at: .modArmorRating,
                on: target,
                subjects: PerkEvaluationSubjects(owner: target)
                    .binding(.item, to: items.conditionSubject(of: worn.item))
            )
            return WornArmorPiece(rating: rating, type: type)
        }
        let values = world.actorValues(of: target)
        let read = { (name: String) -> Float in
            ActorValueIdentity.index(named: name).flatMap { values?($0) } ?? 0
        }
        var rating = WeaponStrikeRules.armorRating(
            pieces: pieces,
            skills: ArmorSkills(light: read("Light Armor"), heavy: read("Heavy Armor")),
            isPlayer: target == .player,
            extra: read("Damage Resist"),
            settings: weaponDamage
        )
        if let blow {
            rating = perkValue(
                rating,
                at: .modTargetDamageResistance,
                on: blow.attacker,
                subjects: attackSubjects(blow, on: target)
            )
        }
        return WeaponStrikeRules.armorFraction(
            rating: rating,
            pieces: pieces,
            settings: weaponDamage
        )
    }
}
