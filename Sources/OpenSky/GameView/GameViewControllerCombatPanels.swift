// The combat and magic panels forward to the coordinators that own them.

import OpenSkyCombat
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyPhysics

extension GameViewController: MeleeCombatControlProviding {
    var meleeCombatSnapshot: MeleeCombatSnapshot {
        combat.meleeCombatSnapshot
    }

    var isWeaponDrawn: Bool {
        get { combat.isWeaponDrawn }
        set { combat.isWeaponDrawn = newValue }
    }

    @discardableResult
    func requestMeleeAttack() -> MeleeActionOutcome {
        combat.requestMeleeAttack()
    }

    @discardableResult
    func requestMeleePowerAttack() -> MeleeActionOutcome {
        combat.requestMeleePowerAttack()
    }

    func clearMeleeTrace() {
        combat.clearMeleeTrace()
    }
}

extension GameViewController: ArcheryControlProviding {
    var archerySnapshot: ArcherySnapshot {
        combat.archerySnapshot
    }

    @discardableResult
    func spawnDevProjectile() -> ArcheryActionOutcome {
        combat.spawnDevProjectile()
    }

    func despawnProjectiles() {
        combat.despawnProjectiles()
        combatWorld.run(combat.takeCommands())
    }

    func clearStuckProjectiles() {
        combat.clearStuckProjectiles()
        combatWorld.run(combat.takeCommands())
    }

    func clearProjectileTrace() {
        combat.clearProjectileTrace()
    }
}

extension GameViewController: CombatLoopControlProviding {
    var combatLoopSnapshot: CombatLoopSnapshot {
        combat.combatLoopSnapshot
    }

    var selectedCombatStyle: CombatStyleReadout? {
        combat.selectedCombatStyle
    }

    var selectedActorIsHostile: Bool {
        get { combat.selectedActorIsHostile }
        set { combat.selectedActorIsHostile = newValue }
    }

    var isActorCastingEnabled: Bool {
        get { combat.isActorCastingEnabled }
        set { combat.isActorCastingEnabled = newValue }
    }

    var usesCombatTemperament: Bool {
        get { combat.usesCombatTemperament }
        set { playerSettingsStore.set(.combatTemperament, to: newValue ? 1 : 0) }
    }

    func clearCombatTrace() {
        combat.clearCombatTrace()
    }
}

extension GameViewController: MagicEffectControlProviding {
    var magicEffectControlSnapshot: MagicEffectControlSnapshot {
        magic.magicEffectControlSnapshot
    }

    @discardableResult
    func consumeFirstCarriedMagicItem() -> MagicEffectActionOutcome {
        magic.consumeFirstCarriedMagicItem()
    }

    @discardableResult
    func dispelPlayerMagicEffects() -> MagicEffectActionOutcome {
        magic.dispelPlayerMagicEffects()
    }
}

extension GameViewController: CastingControlProviding {
    var castingControlSnapshot: CastingControlSnapshot {
        magic.castingControlSnapshot
    }

    @discardableResult
    func grantPlayerStartSpells() -> CastingActionOutcome {
        magic.grantPlayerStartSpells()
    }

    @discardableResult
    func readFirstCarriedSpellTome() -> CastingActionOutcome {
        magic.readFirstCarriedSpellTome()
    }

    @discardableResult
    func readFirstUnreadSkillBook() -> CastingActionOutcome {
        magic.readFirstUnreadSkillBook()
    }

    @discardableResult
    func selectNextKnownSpell() -> CastingActionOutcome {
        magic.selectNextKnownSpell()
    }

    @discardableResult
    func readySelectedSpell(in hand: SpellHand) -> CastingActionOutcome {
        magic.readySelectedSpell(in: hand)
    }

    @discardableResult
    func castReadiedSpell(in hand: SpellHand) -> CastingActionOutcome {
        magic.castReadiedSpell(in: hand)
    }
}

extension GameViewController: RagdollControlProviding {
    var ragdollStatsSnapshot: RagdollStatsSnapshot {
        ragdoll.ragdollStatsSnapshot
    }

    @discardableResult
    func triggerRagdoll() -> Bool {
        ragdoll.triggerRagdoll()
    }

    func setRagdollFrozen(_ frozen: Bool) {
        ragdoll.setRagdollFrozen(frozen)
    }

    func setRagdollSelfCollision(_ enabled: Bool) {
        ragdoll.setRagdollSelfCollision(enabled)
    }

    func clearRagdolls() {
        ragdollWorld.run(ragdoll.clearRagdolls())
    }
}
