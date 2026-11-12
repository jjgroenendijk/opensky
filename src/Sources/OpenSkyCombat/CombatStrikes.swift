// The skill, sneak-attack, and armour terms of one weapon hit, read from the
// world. The arithmetic lives in `WeaponStrikeRules`; the perk terms are in
// `CombatPerkTerms`.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyProgressionInterface

extension CombatShared {
    /// The terms of one weapon hit on a target, and the block and stamina reads around it.
    struct CombatStrikes {
        let shared: CombatShared

        /// The terms of `blow` on `target`, perks of both sides included.
        func strike(_ blow: CombatBlow, on target: ReferenceKey) -> WeaponStrike {
            var strike = WeaponStrike()
            let attack = shared.perks.attackSubjects(blow, on: target)
            if
                blow.attacker == .player,
                let index = SkillUseAction.weaponHit(blow.handType).skillIndex,
                let skill = shared.world.actorValues(of: .player)?(index)
            {
                strike.skillMultiplier = WeaponStrikeRules.playerSkillMultiplier(
                    skill: skill, settings: shared.weaponDamage
                )
            }
            if isSneakAttack(by: blow.attacker, on: target) {
                let family = WeaponStrikeRules.sneakMultiplier(
                    handType: blow.handType, settings: shared.weaponDamage
                )
                strike.sneakMultiplier = shared.perks.perkValue(
                    family, at: .modSneakAttackMult, on: blow.attacker, subjects: attack
                )
            }
            strike.armorFraction = armorFraction(of: target, against: blow)
            if
                let mult = shared.world
                    .actorValues(of: blow.attacker)?(ActorValueIndex.attackDamageMult)
            {
                strike.attackDamageMultiplier = mult
            }
            shared.perks.applyPerkTerms(to: &strike, blow: blow, on: target)
            return strike
        }

        /// A sneak attack the player landed: Sneak experience and the HUD notice.
        func reportSneakAttack(_ strike: WeaponStrike, ranged: Bool) {
            guard strike.isSneakAttack else { return }
            let amount = ranged ? shared.weaponDamage.sneakSkillUseRanged : shared.weaponDamage
                .sneakSkillUseMelee
            _ = shared.world.reporter.reportSkillUse(SkillUseEvent(
                actor: .player,
                action: .sneakAttack,
                amount: amount
            ))
            shared.pendingCommands.append(
                .showNotification(shared.weaponDamage
                    .sneakNotice(multiplier: strike.sneakMultiplier))
            )
        }

        /// The blow before the block, so a stronger hit costs more to stop.
        func applyBlockStamina(_ damage: MeleeDamageResult, to blocker: ReferenceKey) {
            let incoming = damage.strike.damage(base: damage.base, attack: damage.attackMultiplier)
            shared.world.damageStamina(
                by: shared.stamina.blockCost(incomingDamage: incoming),
                of: blocker
            )
        }

        /// UESP "Skyrim:Combat": a power attack needs at least one point of stamina.
        func payMeleeStamina(_ cost: Float) -> Bool {
            guard
                let index = ActorValueIdentity.index(named: "Stamina"),
                let stamina = shared.world.actorValues(of: .player)?(index)
            else { return true }
            guard stamina >= 1 else { return false }
            shared.world.damageStamina(by: cost, of: .player)
            return true
        }

        func canPowerBash() -> Bool {
            shared.world.ownsPerk(editorID: "PowerBash", on: .player)
        }

        func combatBlockSkill(of key: ReferenceKey) -> Float {
            ActorValueIdentity.index(named: "Block")
                .flatMap { shared.world.actorValues(of: key)?($0) } ?? MeleeDamage.defaultBlockSkill
        }

        /// UESP "Skyrim:Block": a shield bash uses the shield's base rating, without tempering.
        func meleeBashSource() -> (blockSkill: Float, shieldRating: Float?) {
            (combatBlockSkill(of: .player), shieldRating(of: .player))
        }

        /// The base armour rating of the shield `key` wears, or nil without one.
        func shieldRating(of key: ReferenceKey) -> Float? {
            shared.world.gearReads.equippedItems(of: key).lazy.compactMap { worn -> Float? in
                guard
                    let armor = shared.items?.armor[worn.item.rawValue],
                    armor.bodyTemplate?.slots.contains(.shield) ?? false
                else { return nil }
                return Float(armor.armorRating & 0xFFFF) / 100
            }.first
        }

        /// Only the player sneak attacks: the player has no detection state toward an
        /// NPC. A target already fighting the player knows where the player is.
        func isSneakAttack(by attacker: ReferenceKey, on target: ReferenceKey) -> Bool {
            guard attacker == .player, target != .player else { return false }
            if let loop = shared.loop, loop.activity(of: target) != .notFighting {
                return false
            }
            return !shared.world.awareness(of: target, toward: attacker).isDetected
        }

        /// The fraction of a blow `target`'s worn armour stops. Each piece passes the
        /// wearer's `Mod Armor Rating`, and the sum the attacker's `Mod Target Damage Resistance`.
        func armorFraction(of target: ReferenceKey, against blow: CombatBlow? = nil) -> Float {
            guard let items = shared.items else { return 0 }
            let pieces = shared.world.gearReads.equippedItems(of: target)
                .compactMap { worn -> WornArmorPiece? in
                    guard
                        let armor = items.armor[worn.item.rawValue],
                        let type = armor.bodyTemplate?.armorType
                    else { return nil }
                    let isBody = armor.bodyTemplate?.slots.contains(.body) ?? false
                    let tempered = Float(armor.armorRating & 0xFFFF) / 100
                        + Tempering.bonus(level: worn.temperLevel, isBodyArmor: isBody)
                    let rating = shared.perks.perkValue(
                        tempered,
                        at: .modArmorRating,
                        on: target,
                        subjects: PerkEvaluationSubjects(owner: target)
                            .binding(.item, to: items.conditionSubject(of: worn.item))
                    )
                    return WornArmorPiece(rating: rating, type: type)
                }
            let values = shared.world.actorValues(of: target)
            let read = { (name: String) -> Float in
                ActorValueIdentity.index(named: name).flatMap { values?($0) } ?? 0
            }
            var rating = WeaponStrikeRules.armorRating(
                pieces: pieces,
                skills: ArmorSkills(light: read("Light Armor"), heavy: read("Heavy Armor")),
                isPlayer: target == .player,
                extra: read("Damage Resist"),
                settings: shared.weaponDamage
            )
            if let blow {
                rating = shared.perks.perkValue(
                    rating,
                    at: .modTargetDamageResistance,
                    on: blow.attacker,
                    subjects: shared.perks.attackSubjects(blow, on: target)
                )
            }
            return WeaponStrikeRules.armorFraction(
                rating: rating,
                pieces: pieces,
                settings: shared.weaponDamage
            )
        }

        func meleeBlock(of target: ReferenceKey) -> MeleeBlockKind? {
            let isBlocking = target == .player && shared.melee?.state.isBlocking == true
            return CombatCore.block(
                of: target,
                playerIsBlocking: isBlocking,
                playerShieldRating: isBlocking ? meleeBashSource().shieldRating : nil,
                machineBlock: target == .player ? nil : npcBlock(of: target)
            )
        }

        /// An NPC with a shield blocks with it, so the shield formula applies (UESP
        /// "Skyrim:Block").
        func npcBlock(of target: ReferenceKey) -> MeleeBlockKind? {
            guard let kind = shared.loop?.blockKind(of: target) else { return nil }
            return shieldRating(of: target)
                .map { MeleeBlockKind.shield(baseArmorRating: $0) } ?? kind
        }
    }
}
