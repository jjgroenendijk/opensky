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

    public func playerCasting() -> PlayerCastingReadout? {
        guard let caster else { return nil }
        let book = world.actorValueHolder(for: .player).map(caster.spellbook.state(of:))
        let hands = SpellHand.allCases.map { hand in
            PlayerCastingHand(
                hand: hand,
                phase: caster.phase(of: hand, on: .player),
                spell: caster.state(of: hand, on: .player).spell,
                readied: book?.spell(in: hand),
                pressed: castingState.castPressed.contains(hand),
                heldBySheathedPress: castingState.sheathedPress.contains(hand),
                wantsCast: castingCues.wantsCast(hand)
            )
        }
        return PlayerCastingReadout(hands: hands, cues: castingCues.castingCueText)
    }
}
