// The world of the player's melee runtime. Each answer reads a combat part, a
// `CombatCore` rule, or one `CombatWorld` member.

import OpenSkyActorsInterface
import OpenSkyBehavior
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyProgressionInterface
import OpenSkyWorldState
import simd

/// What the melee runtime reads and changes, over the shared combat state.
final class CombatMeleeWorldPart: CombatSharedPart, MeleeCombatWorld {
    var meleeAttacker: MeleeAttacker {
        shared.meleeAttacker
    }

    func meleeAttackMultiplier(handType: CombatHandType) -> Float {
        guard let values = shared.world.actorValues(of: .player) else { return 1 }
        return CombatFortifyBonus.melee(handType: handType, reading: values)
    }

    func meleeTargets() -> [MeleeTarget] {
        shared.world.residentActors().map { MeleeTarget(key: $0.key, feet: $0.feet) }
    }

    func meleeBlock(of target: ReferenceKey) -> MeleeBlockKind? {
        shared.strikes.meleeBlock(of: target)
    }

    func meleeBlockSkill(of target: ReferenceKey) -> Float {
        shared.strikes.combatBlockSkill(of: target)
    }

    func meleeBlockMultiplier(of target: ReferenceKey) -> Float {
        shared.perks.blockMultiplier(of: target)
    }

    func meleeStrike(_ blow: CombatBlow, on target: ReferenceKey) -> WeaponStrike {
        let strikes = shared.strikes
        let strike = strikes.strike(blow, on: target)
        strikes.reportSneakAttack(strike, ranged: false)
        return strike
    }

    func meleeResolvedWeapon(_ weapon: FormID?) -> ResolvedFormID? {
        shared.items?.conditionSubject(of: weapon)?.id
    }

    func meleeSweeps(_ blow: CombatBlow) -> Bool {
        shared.perks.perkSweeps(blow)
    }

    func applyMeleeHitSpell(_ blow: CombatBlow, on target: ReferenceKey) {
        shared.perks.applyPerkHitSpell(blow, on: target)
    }

    func meleePowerAttackStamina(_ cost: Float, weapon: FormID?) -> Float {
        shared.perks.powerAttackStamina(cost, weapon: weapon)
    }

    func applyBlockStamina(_ damage: MeleeDamageResult, to blocker: ReferenceKey) {
        shared.strikes.applyBlockStamina(damage, to: blocker)
    }

    func payMeleeStamina(_ cost: Float) -> Bool {
        shared.strikes.payMeleeStamina(cost)
    }

    func canPowerBash() -> Bool {
        shared.strikes.canPowerBash()
    }

    func meleeBashSource() -> (blockSkill: Float, shieldRating: Float?) {
        shared.strikes.meleeBashSource()
    }

    /// The player's own swing: the melee runtime only ever swings for the player.
    @discardableResult
    func applyMeleeDamage(_ amount: Float, to target: ReferenceKey) -> Bool {
        let melee = shared.melee
        let standingPower = melee?.strikeKind == .power && melee?.powerDirection == .inPlace
        let damage = shared.damage
        let severs = standingPower && melee
            .map { damage.canSever(handType: $0.weapon.handType) } == true
        return damage.applyHealthDamage(
            amount, to: target, attacker: meleeAttacker.key, kind: .melee, canSever: severs
        )
    }

    func playMeleeImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>) {
        shared.pendingCommands.append(.playImpact(impact, at: position))
    }

    @discardableResult
    func startMeleeKillMove(on target: ReferenceKey, damage: Float, power: Bool) -> Bool {
        shared.damage.startMeleeKillMove(on: target, damage: damage, power: power)
    }
}

extension CombatMeleeWorldPart {
    func makeRuntime(_ data: CombatSessionData) -> MeleeCombatRuntime {
        let runtime = MeleeCombatRuntime(settings: data.combat, world: self)
        runtime.impacts = data.impacts
        runtime.powerAttacks = data.powerAttacks
        runtime.skillUses = data.skillUses
        runtime.staggers = data.staggers
        return runtime
    }
}
