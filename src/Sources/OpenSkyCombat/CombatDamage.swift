// Health damage in combat: difficulty, knock-back, reflected blows, falls, and the
// kill rule of a kill move. See docs/engine/combat.md and docs/engine/impulses.md#hits.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyProgressionInterface
import simd

extension CombatShared {
    /// Where every combat hit, fall, and kill-move test turns into health damage.
    struct CombatDamage {
        let shared: CombatShared

        /// Every weapon, arrow, and explosion hit passes here, so difficulty scales
        /// health damage at one point. A nil attacker is never the player. An ethereal
        /// actor deals and takes none.
        @discardableResult
        func applyHealthDamage(
            _ amount: Float,
            to target: ReferenceKey,
            attacker: ReferenceKey?,
            kind: CombatHitKind = .other,
            canSever: Bool = false
        ) -> Bool {
            guard amount > 0, !isEthereal(target), !(attacker.map(isEthereal) ?? false)
            else { return false }
            let scaled = DifficultyDamage.scaled(
                amount, attackerIsPlayer: attacker == .player, targetIsPlayer: target == .player,
                multipliers: difficultyMultipliers
            ) * (shared.world.isInKillMove(target) ? KillMoveAttempt.damageMultiplier : 1)
            let health = shared.world.health(of: target)
            let landed = shared.world.damageHealth(by: scaled, of: target)
            if landed, let health, let attacker {
                knockBack(target, damage: scaled, health: health, by: (attacker, kind))
            }
            if landed, attacker == .player, target != .player {
                shared.playerStruckTarget = target
            }
            if landed {
                let hit = CombatHitRecord(
                    damage: scaled, kind: kind, attacker: attacker, canSever: canSever
                )
                shared.world.recordHealthHit(hit, on: target)
                if kind != .other {
                    shared.pendingCommands.append(.drewBlood(hit, target: target))
                }
                if kind == .melee, let attacker {
                    reflectMeleeDamage(amount, from: target, to: attacker)
                }
            }
            return landed
        }

        /// UESP "Skyrim:One-handed" and "Skyrim:Two-handed": Savage Strike and Devastating
        /// Blow let a standing power attack decapitate. Maces and warhammers count, as in
        /// the unpatched game.
        func canSever(handType: CombatHandType, attacker: ReferenceKey = .player) -> Bool {
            switch handType {
            case .sword, .dagger, .axe, .mace:
                shared.world.ownsPerk(editorID: "SavageStrike", on: attacker)
            case .greatsword, .battleaxe:
                shared.world.ownsPerk(editorID: "DevastatingBlow", on: attacker)
            default:
                false
            }
        }

        func isEthereal(_ key: ReferenceKey) -> Bool {
            shared.world.gearReads.magicInfluence(of: key).isEthereal
        }

        /// The impulse runtime the explosions share. Nil pushes nothing.
        var impulses: ImpulseRuntime? {
            shared.explosions.impulses
        }

        /// Knocks `target` back as a melee hit of `damage` from the player would, without
        /// the damage. Nil when the hit is too weak or the target cannot be pushed.
        @discardableResult
        func forceKnockBack(_ target: ReferenceKey, damage: Float) -> HitKnock? {
            guard let health = shared.world.health(of: target) else { return nil }
            return knockBack(target, damage: damage, health: health, by: (.player, .melee))
        }

        /// Knocks `target` back after a melee hit of `damage` that found it at `health`. A
        /// blocked hit, or a ranged one, pushes no actor.
        @discardableResult
        func knockBack(
            _ target: ReferenceKey, damage: Float, health: (current: Float, maximum: Float),
            by blow: (attacker: ReferenceKey, kind: CombatHitKind)
        ) -> HitKnock? {
            let (attacker, kind) = blow
            guard
                kind == .melee, shared.strikes.meleeBlock(of: target) == nil,
                let impulses, let world = impulses.world, world.isPushable(target),
                let from = feet(of: attacker), let to = feet(of: target)
            else { return nil }
            let roll = Float(shared.perks.random.percent()) / 100
            guard let knock = HitKnockback.knock(
                damage: damage, health: health, roll: roll, settings: impulses.settings
            ) else { return nil }
            let away = SIMD3(to.x - from.x, to.y - from.y, 0)
            guard simd_length(away) > 0.001 else { return nil }
            let velocity = simd_normalize(away) * knock.speed
            let pushed = knock.isKnockdown
                ? world.knockDown(
                    target, from: from, magnitude: knock.speed / GameplayImpulse.havokScale
                )
                : world.knockActor(target, velocity: velocity, knockdown: false)
            guard pushed else { return nil }
            impulses.record(.knock(
                target,
                speed: knock.speed,
                knockdown: knock.isKnockdown,
                cause: .melee
            ))
            return knock
        }

        func feet(of key: ReferenceKey) -> SIMD3<Float>? {
            key == .player ? shared.meleeAttacker.feet : shared.world.residentActor(key: key)?.feet
        }

        /// The defender's `Reflect Damage` is a percent chance. A reflected blow does not
        /// spare the defender, and it is the damage after armour and block, so UESP's
        /// "reduced by the defender's armour" holds. The defender counts as the attacker
        /// for difficulty: a player's reflected blow is scaled by "player deals".
        func reflectMeleeDamage(
            _ amount: Float,
            from defender: ReferenceKey,
            to attacker: ReferenceKey
        ) {
            guard
                attacker != defender,
                let chance = shared.world.actorValues(of: defender)?(ActorValueIndex.reflectDamage),
                chance > 0,
                Float(shared.perks.random.percent()) < chance
            else { return }
            // `.other`, so the reflected blow cannot reflect again.
            applyHealthDamage(amount, to: attacker, attacker: defender, kind: .other)
        }

        /// Hurts `actor` for a fall of `height` units that landed at `speed`. Water ends a
        /// fall before it lands, so a caller never reports one. Returns the damage dealt.
        @discardableResult
        func applyFall(height: Float, speed: Float, to actor: ReferenceKey) -> Float {
            let damage = fallDamage(height: height, speed: speed, to: actor)
            if damage > 0 {
                _ = shared.world.damageHealth(by: damage, of: actor)
                shared.world.recordHealthHit(
                    CombatHitRecord(damage: damage, kind: .other),
                    on: actor
                )
            }
            shared.lastFall = FallOutcome(
                actor: actor,
                height: height,
                speed: speed,
                damage: damage
            )
            return damage
        }

        func fallDamage(height: Float, speed: Float, to actor: ReferenceKey) -> Float {
            let isPlayer = actor == .player
            let base = shared.falls.damage(height: height, speed: speed, isPlayer: isPlayer)
            let influence = shared.world.gearReads.magicInfluence(of: actor)
            guard base > 0, !influence.isEthereal, !influence.isParalysed else { return 0 }
            let perked = shared.perks.perkValue(
                base, at: .modFallingDamage, on: actor,
                subjects: PerkEvaluationSubjects(owner: actor)
            )
            // UESP: easier levels lower the player's fall damage; harder ones do not raise it.
            let scale = isPlayer ? min(difficultyMultipliers.damageToPlayer.value, 1) : 1
            return max(perked * scale, 0)
        }

        var difficultyMultipliers: DifficultyMultipliers {
            shared.difficultySettings.multipliers(shared.difficulty)
        }

        /// The player's Destruction spell use, with its experience divided above Adept.
        /// Any other use passes through unchanged.
        func adjustingForDifficulty(_ use: SkillUseEvent) -> SkillUseEvent {
            guard
                use.actor == .player,
                case let .spellEffect(skill) = use.action,
                skill == Self.destructionIndex
            else { return use }
            return SkillUseEvent(
                actor: use.actor, action: use.action,
                amount: DifficultyDamage.destructionExperience(
                    use.amount, level: shared.difficulty, multipliers: difficultyMultipliers
                )
            )
        }

        /// `Destruction` in `wbActorValueEnum`.
        static let destructionIndex: Int32 = 20

        /// The attack kills when its hit, after difficulty, takes the target's health to zero
        /// and zero health kills the target.
        @discardableResult
        func startMeleeKillMove(on target: ReferenceKey, damage: Float, power: Bool) -> Bool {
            let attacker = shared.meleeAttacker.key
            return shared.world.startKillMove(KillMoveAttempt(
                attacker: attacker,
                target: target,
                action: power ? KillMoveAttempt.powerAttackAction : KillMoveAttempt.attackAction,
                kills: attackKills(target, damage: damage, attacker: attacker)
            ))
        }

        /// An NPC's kill move. The player's own death has its own camera, so an NPC kill
        /// move takes only another NPC.
        func startCombatKillMove(
            by actor: ReferenceKey, on target: ReferenceKey, damage: Float
        ) -> Bool {
            guard target != .player else { return false }
            return shared.world.startKillMove(KillMoveAttempt(
                attacker: actor, target: target, action: KillMoveAttempt.attackAction,
                kills: attackKills(target, damage: damage, attacker: actor)
            ))
        }

        func attackKills(_ target: ReferenceKey, damage: Float, attacker: ReferenceKey) -> Bool {
            guard
                let health = shared.world.health(of: target), health.current > 0,
                damage > 0
            else {
                return false
            }
            let scaled = DifficultyDamage.scaled(
                damage, attackerIsPlayer: attacker == .player, targetIsPlayer: target == .player,
                multipliers: difficultyMultipliers
            )
            return health.current - scaled <= 0 && shared.world.canBeKilled(target, by: attacker)
        }
    }
}
