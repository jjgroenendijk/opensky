// Maintained casts: drain magicka while a concentration spell is held, apply its
// effects once a second, and stop when magicka runs out or the release is due
// (<https://en.uesp.net/wiki/Skyrim:Magic_Overview>). See docs/engine/spellcasting.md.

import Foundation
import OpenSkyActorsInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyMagicInterface

extension CasterRuntime {
    /// The spell-fire event reached a concentration hand waiting in `.ready`: the cost
    /// is checked here, and a cast that cannot pay resets the hand.
    @discardableResult
    public func fire(_ hand: SpellHand, on caster: ActorValueHolder) -> SpellCastOutcome {
        let hand = leadHand(of: hand, on: caster.key)
        let state = state(of: hand, on: caster.key)
        guard
            state.phase == .ready, let key = state.spell, let spell = castable(key),
            spell.data?.castingType == .concentration
        else { return .ignored }
        let cost = castCost(of: spell, dual: state.isDualCast, caster: caster)
        let available = pool(for: spell, caster: caster)
        guard cost <= available else {
            casts[slot(hand, caster)] = SpellCastState()
            endDualPartner(of: hand, lead: state, caster: caster)
            return record(hand, on: caster, .failed(spell.isStaff
                    ? .staffOutOfCharge(cost: cost, available: available)
                    : .insufficientMagicka(cost: cost, available: available)))
        }
        return record(hand, on: caster, startConcentration(hand, spell: spell, caster: caster))
    }

    /// A concentration hand in `.ready` whose graph raised no spell-fire event fires
    /// after the same wait a fire-and-forget release gets.
    func awaitSpellFire(
        _ hand: SpellHand, spell: ResolvedSpell, delta: Float, caster: ActorValueHolder
    ) {
        guard spell.data?.castingType == .concentration else { return }
        var state = state(of: hand, on: caster.key)
        state.addFireWait(delta)
        casts[slot(hand, caster)] = state
        guard state.fireWait >= SpellReleaseLatch.fireWithoutGraphAfter else { return }
        fire(hand, on: caster)
    }

    /// Enters the held state: the drain starts and the first application lands now
    /// rather than a second later, so a maintained heal heals when it starts costing.
    func startConcentration(
        _ hand: SpellHand, spell: ResolvedSpell, caster: ActorValueHolder
    ) -> SpellCastOutcome {
        var state = state(of: hand, on: caster.key)
        state.beginConcentration()
        casts[slot(hand, caster)] = state
        world?.spellWasCast(spell.key, by: caster.key)
        applyOnce(hand, spell: spell, caster: caster)
        return .concentrating(
            spell: spell.key,
            costPerSecond: castCost(of: spell, dual: state.isDualCast, caster: caster)
        )
    }

    /// One frame of a maintained cast: drain, apply the whole seconds that
    /// elapsed, and stop when the magicka runs out or the release is due.
    func maintain(
        _ hand: SpellHand,
        spell: ResolvedSpell,
        delta: Float,
        caster: ActorValueHolder
    ) -> SpellCastOutcome {
        var running = state(of: hand, on: caster.key)
        let perSecond = castCost(of: spell, dual: running.isDualCast, caster: caster)
        let available = pool(for: spell, caster: caster)
        let drain = perSecond * delta
        guard drain <= available else {
            // Take what is left rather than nothing: the caster paid for the
            // fraction of a second they got before the pool ran dry.
            pay(available, for: spell, caster: caster)
            casts[slot(hand, caster)] = SpellCastState()
            endDualPartner(of: hand, lead: running, caster: caster)
            return .failed(spell.isStaff
                ? .staffOutOfCharge(cost: drain, available: available)
                : .insufficientMagicka(cost: drain, available: available))
        }
        pay(drain, for: spell, caster: caster)
        noteSkillUse(of: spell, amount: drain, caster: caster)
        running.spend(drain)
        running.addHeld(delta)
        casts[slot(hand, caster)] = running
        let pending = running.pendingApplications(limit: Self.maximumApplicationsPerAdvance)
        for _ in 0 ..< pending {
            applyOnce(hand, spell: spell, caster: caster)
        }
        let minimum = max(0, spell.data?.castDuration ?? 0)
        let after = state(of: hand, on: caster.key)
        guard after.isReleasing, after.held >= minimum else {
            return .concentrating(spell: spell.key, costPerSecond: perSecond)
        }
        return stopConcentration(hand, spell: spell.key, caster: caster)
    }

    /// One application of a maintained spell's effect list.
    func applyOnce(
        _ hand: SpellHand,
        spell: ResolvedSpell,
        caster: ActorValueHolder
    ) {
        var state = state(of: hand, on: caster.key)
        state.noteApplied()
        casts[slot(hand, caster)] = state
        _ = apply(spell, caster: caster, dual: state.isDualCast)
        tally.noteConcentrationSecond()
    }

    public func stopConcentration(
        _ hand: SpellHand,
        spell: ReferenceKey,
        caster: ActorValueHolder
    ) -> SpellCastOutcome {
        let state = state(of: hand, on: caster.key)
        casts[slot(hand, caster)] = SpellCastState()
        endDualPartner(of: hand, lead: state, caster: caster)
        tally.noteCast()
        return .released(
            spell: spell,
            heldSeconds: state.held,
            magickaSpent: state.magickaSpent
        )
    }
}
