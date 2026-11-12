// The MagicPort calls, each answered by the part that owns it.

import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
public import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyProgressionInterface
import OpenSkyWorldState
import simd

extension MagicCoordinator {
    public func noteEffectsRestored() {
        abilityReconciler.noteEffectsRestored()
    }

    public func wantsCast(_ hand: SpellHand) -> Bool {
        castingCues.wantsCast(hand)
    }

    public func magicConditionResolution() -> MagicConditionResolution {
        conditionReads.magicConditionResolution()
    }

    public var playerGrabbedReference: ReferenceKey? {
        holdEffects.playerGrabbedReference
    }

    public func playerKnownSpells() -> [ResolvedSpell] {
        controlPanels.playerKnownSpells()
    }

    public func raceEffectLinks(base: FormID, actor: ReferenceKey) -> [SpellHitEffectLinks] {
        raceEffects.raceEffectLinks(base: base, actor: actor)
    }

    public var timeScales: MagicTimeScales {
        slowTimeClock.timeScales
    }

    public var summonFades: [ReferenceKey: Float] {
        summonCommands.summonFades
    }

    @discardableResult
    public func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
        casterBridge.applySpellHit(hit)
    }

    public func playerStaff() -> (staff: HeldStaff, charge: EnchantmentCharge)? {
        heldStaves.playerStaff()
    }
}
