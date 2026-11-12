// The calls every combat world forwards to the world's reporter and the player's
// behavior graph.

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

/// The base of the combat world parts. The reporting and graph calls a runtime makes
/// go to the world.
class CombatSharedPart {
    let shared: CombatShared

    init(shared: CombatShared) {
        self.shared = shared
    }

    @discardableResult
    func reportScriptHit(_ hit: ScriptHitEvent) -> Int {
        shared.world.reporter.reportScriptHit(hit)
    }

    @discardableResult
    func reportSkillUse(_ use: SkillUseEvent) -> Float {
        shared.world.reporter.reportSkillUse(use)
    }

    @discardableResult
    func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
        shared.world.reporter.applySpellHit(hit)
    }

    @discardableResult
    func applyWeaponEnchantment(_ hit: WeaponEnchantmentHit) -> WeaponEnchantmentReport? {
        shared.world.reporter.applyWeaponEnchantment(hit)
    }

    func applyWeaponPoison(_ hit: WeaponPoisonHit) {
        shared.world.reporter.applyWeaponPoison(hit)
    }

    @discardableResult
    func applyWeaponEnhancement(attacker: ReferenceKey, target: ReferenceKey) -> Int {
        shared.world.reporter.applyWeaponEnhancement(attacker: attacker, target: target)
    }

    func spellLanded(_ payload: SpellPayload, at point: SIMD3<Float>) {
        shared.world.reporter.spellLanded(payload, at: point)
    }

    /// Only the player carries a behavior graph, so an event on an NPC
    /// answers false.
    @discardableResult
    func raiseCombatEvent(_ name: String, on target: ReferenceKey?) -> Bool {
        guard let target, target != .player else { return shared.world.raisePlayerGraphEvent(name) }
        return shared.world.raiseActorGraphEvent(name, on: target)
    }

    func writeCombatVariable(_ value: BehaviorVariableValue, named name: String) {
        shared.world.writePlayerGraphVariable(value, named: name)
    }

    func writeCombatVariable(
        _ value: BehaviorVariableValue, named name: String, on target: ReferenceKey?
    ) {
        guard let target, target != .player else {
            shared.world.writePlayerGraphVariable(value, named: name)
            return
        }
        shared.world.writeActorGraphVariable(value, named: name, on: target)
    }

    func impactMaterial(of target: ReferenceKey) -> FormID? {
        shared.world.impactMaterial(of: target)
    }

    func showDefaultBlood(on target: ReferenceKey, at position: SIMD3<Float>, melee: Bool) {
        shared.pendingCommands.append(.showDefaultBlood(on: target, at: position, melee: melee))
    }
}
