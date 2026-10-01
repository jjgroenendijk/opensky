// Maintained casts: drain magicka while a concentration spell is held, apply its
// effects once a second, and stop when magicka runs out or the release is due
// (<https://en.uesp.net/wiki/Skyrim:Magic_Overview>). See docs/engine/spellcasting.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface

extension CasterRuntime {
    /// One frame of a maintained cast: drain, apply the whole seconds that
    /// elapsed, and stop when the magicka runs out or the release is due.
    public func maintain(
        _ hand: SpellHand,
        spell: ResolvedSpell,
        delta: Float,
        caster: ActorValueHolder
    ) -> SpellCastOutcome {
        var running = state(of: hand, on: caster.key)
        let perSecond = cost(of: spell, caster: caster)
        let available = values.current(of: caster).magicka
        let drain = perSecond * delta
        guard drain <= available else {
            // Take what is left rather than nothing: the caster paid for the
            // fraction of a second they got before the pool ran dry.
            values.damage(.magicka, by: available, on: caster)
            casts[slot(hand, caster)] = SpellCastState()
            return .failed(.insufficientMagicka(cost: drain, available: available))
        }
        values.damage(.magicka, by: drain, on: caster)
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
    public func applyOnce(
        _ hand: SpellHand,
        spell: ResolvedSpell,
        caster: ActorValueHolder
    ) {
        var state = state(of: hand, on: caster.key)
        state.noteApplied()
        casts[slot(hand, caster)] = state
        _ = apply(spell, caster: caster)
        tally.noteConcentrationSecond()
    }

    public func stopConcentration(
        _ hand: SpellHand,
        spell: ReferenceKey,
        caster: ActorValueHolder
    ) -> SpellCastOutcome {
        let state = state(of: hand, on: caster.key)
        casts[slot(hand, caster)] = SpellCastState()
        tally.noteCast()
        return .released(
            spell: spell,
            heldSeconds: state.held,
            magickaSpent: state.magickaSpent
        )
    }
}
