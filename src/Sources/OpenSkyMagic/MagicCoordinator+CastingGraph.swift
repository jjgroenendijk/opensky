// The casting hands' behaviour graph events: each frame compares every hand with the
// last and raises the start, ready, and release events on the caster's graph. An NPC's
// graph also gets its `bWantCast` flags. See docs/engine/casting-graph.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface

extension MagicCoordinator.CastingCueTracker {
    /// Raises the start events of the casts that began last step. The player's single
    /// start waits while the other hand may still join it, as the game holds the first
    /// press (docs/engine/casting-graph.md, A dual cast).
    func raisePendingStarts() {
        let pending = coordinator.castingState.pendingStarts
        coordinator.castingState.pendingStarts = []
        for (slot, event) in pending {
            guard
                let state = coordinator.caster?.state(of: slot.hand, on: slot.caster),
                CastingGraphEventRule.startStillHolds(
                    event, phase: state.phase, dual: state.isDualCast
                )
            else { continue }
            if slot.caster == .player, !state.isDualCast, awaitsPartner(slot) {
                coordinator.castingState.pendingStarts.append((slot, event))
                continue
            }
            raise(event, by: slot.caster)
            guard let hand = coordinator.castingState.graphHands[slot] else { continue }
            for next in CastingGraphEventRule.afterStart(slot.hand, state: hand) {
                raise(next, by: slot.caster)
            }
        }
    }

    /// Compares one hand with the last frame and raises what changed.
    func advanceGraphEvents(of slot: CastSlot, state: SpellCastState, cast: Bool) {
        let old = coordinator.castingState.graphHands[slot] ?? CastingGraphHand()
        let new = graphHand(of: state, slot: slot)
        if slot.caster != .player, old.phase.isCasting != new.phase.isCasting {
            coordinator.pendingCommands.append(.actorGraphFlag(
                CastingGraphNames.wantCast(slot.hand), value: new.phase.isCasting,
                actor: slot.caster
            ))
        }
        if let start = CastingGraphEventRule.start(of: slot.hand, from: old, to: new) {
            coordinator.castingState.pendingStarts.append((slot, start))
        }
        for event in CastingGraphEventRule.events(slot.hand, from: old, to: new, cast: cast) {
            raise(event, by: slot.caster)
        }
        coordinator.castingState.graphHands[slot] = new.phase == .idle ? nil : new
    }

    private func awaitsPartner(_ slot: CastSlot) -> Bool {
        guard
            let caster = coordinator.caster,
            let holder = coordinator.world.actorValueHolder(for: slot.caster)
        else { return false }
        return caster.awaitsDualPartner(slot.hand, on: holder)
    }

    private func raise(_ event: String, by caster: ReferenceKey) {
        coordinator.pendingCommands.append(
            caster == .player ? .playerGraphEvent(event) : .actorGraphEvent(event, actor: caster)
        )
        coordinator.castingState.lastGraphEvent = event
    }

    private func graphHand(of state: SpellCastState, slot: CastSlot) -> CastingGraphHand {
        var hand = CastingGraphHand(phase: state.phase, spell: state.spell)
        hand.isDualLead = state.dualRole == .lead
        hand.isDualPartner = state.dualRole == .partner
        hand.isReleasing = slot.caster == .player
            && coordinator.castingState.releaseLatch.isWaiting(slot.hand)
        guard
            let spell = state.spell.flatMap({ coordinator.caster?.spellbook.record($0) }),
            let data = spell.data
        else { return hand }
        hand.isConcentration = data.castingType == .concentration
        var graphSpell = CastGraphSpell(castingType: data.castingType, delivery: data.delivery)
        if let store = coordinator.effects?.effects {
            // A ward spell's keyword may sit on a second effect, as Lesser Ward's does.
            let keywords = spell.effects.compactMap(\.effect)
                .reduce(into: Set<ReferenceKey>()) { $0.formUnion(store.keywordKeys(of: $1)) }
            let named = { (name: String) in
                coordinator.world.keyword(editorID: name).map(keywords.contains) == true
            }
            graphSpell.isWard = named("MagicWard")
            graphSpell.isTelekinesis = named("MagicTelekinesis")
        }
        hand.start = graphSpell.startEvent
        return hand
    }
}
