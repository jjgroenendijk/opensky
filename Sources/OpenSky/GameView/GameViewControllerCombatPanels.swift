// The combat and magic panels forward to the coordinators that own them.

import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyCombat
import OpenSkyCrime
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyProgression
import OpenSkyRendering
import OpenSkyScriptingInterface
import OpenSkyWorld

extension GameViewController: MeleeCombatControlProviding {
    var meleeCombatSnapshot: MeleeCombatSnapshot {
        combat.meleeCombatSnapshot
    }

    var isWeaponDrawn: Bool {
        get { combat.isWeaponDrawn }
        set { combat.isWeaponDrawn = newValue }
    }

    @discardableResult
    func requestMeleeAttack() -> String {
        combat.requestMeleeAttack()
    }

    @discardableResult
    func requestMeleePowerAttack() -> String {
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
    func spawnDevProjectile() -> String {
        combat.spawnDevProjectile()
    }

    func despawnProjectiles() {
        combat.despawnProjectiles()
    }

    func clearStuckProjectiles() {
        combat.clearStuckProjectiles()
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

    func clearCombatTrace() {
        combat.clearCombatTrace()
    }
}

extension GameViewController: MagicEffectControlProviding {
    var magicEffectControlSnapshot: MagicEffectControlSnapshot {
        magic.magicEffectControlSnapshot
    }

    @discardableResult
    func consumeFirstCarriedMagicItem() -> String {
        magic.consumeFirstCarriedMagicItem()
    }

    @discardableResult
    func dispelPlayerMagicEffects() -> String {
        magic.dispelPlayerMagicEffects()
    }
}

extension GameViewController: CastingControlProviding {
    var castingControlSnapshot: CastingControlSnapshot {
        magic.castingControlSnapshot
    }

    @discardableResult
    func grantPlayerStartSpells() -> String {
        magic.grantPlayerStartSpells()
    }

    @discardableResult
    func readFirstCarriedSpellTome() -> String {
        magic.readFirstCarriedSpellTome()
    }

    @discardableResult
    func readFirstUnreadSkillBook() -> String {
        magic.readFirstUnreadSkillBook()
    }

    @discardableResult
    func selectNextKnownSpell() -> String {
        magic.selectNextKnownSpell()
    }

    @discardableResult
    func readySelectedSpell(in hand: SpellHand) -> String {
        magic.readySelectedSpell(in: hand)
    }

    @discardableResult
    func castReadiedSpell(in hand: SpellHand) -> String {
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
        ragdoll.clearRagdolls()
    }
}
