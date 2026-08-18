// The magic half of the native-to-world seam (issue #474, roadmap item 19.11):
// what a spell-facing native is allowed to ask of the session, and the
// nonisolated hops the native bodies actually call.
//
// A protocol of its own that `PapyrusWorldBridge` refines, exactly as the quest
// and actor halves are, and for the same reason: magic is a subsystem with its
// own vocabulary — known spells, readied hands, active effects, a cast — and a
// test that only cares about spells should be able to read this list on its
// own.
//
// ## Why the reads come back as one observation
//
// `spellState(for:)` answers with a whole `PapyrusSpellState` rather than with
// one getter per question, for the reason `actorState(for:)` does. Five natives
// read this actor's magic and three of them are the same two components at
// different angles; taking one observation is what stops `HasSpell` and
// `GetEquippedSpell` from straddling a mutation inside one script line.
//
// ## Nothing here writes around the subsystems that own the state
//
// Learning and forgetting go through `SpellbookRuntime`, so a script's
// `AddSpell` lands in the journal, the dirty counts and the save exactly as
// reading a spell tome does, and readying a hand arbitrates against worn
// equipment through the same path the panel's Ready button takes. Dispelling
// goes through `ActiveEffectRuntime`, so the temporary modifier slots each
// effect owned are handed back rather than leaked. `Spell.Cast` goes through
// `CasterRuntime`, so a scripted cast applies its effect list through the one
// implementation a player's cast uses.
//
// Documented in docs/engine/papyrus-vm.md.

import Foundation

/// One actor's magic as a Papyrus native sees it.
nonisolated struct PapyrusSpellState: Equatable, Sendable {
    /// SPEL and SCRL records this actor knows.
    let knownSpells: Set<ReferenceKey>
    /// The MGEF behind every effect currently acting on this actor.
    let activeEffects: Set<ReferenceKey>
    /// Every keyword those effects carry, resolved once so
    /// `HasMagicEffectWithKeyword` is a set membership test rather than a walk
    /// back through the record store.
    let effectKeywords: Set<ReferenceKey>
    /// The spell readied in each hand, absent for a hand holding none.
    let handSpells: [SpellHand: ReferenceKey]

    init(
        knownSpells: Set<ReferenceKey> = [],
        activeEffects: Set<ReferenceKey> = [],
        effectKeywords: Set<ReferenceKey> = [],
        handSpells: [SpellHand: ReferenceKey] = [:]
    ) {
        self.knownSpells = knownSpells
        self.activeEffects = activeEffects
        self.effectKeywords = effectKeywords
        self.handSpells = handSpells
    }
}

/// Magic state and mutations a Papyrus native may perform.
///
/// `Sendable` for the reason `PapyrusWorldActorBridge` is: every conformer is a
/// `@MainActor` class, and the existential only needed to say so before
/// `PapyrusWorldAccess` can carry it across its hops.
@MainActor
protocol PapyrusWorldMagicBridge: AnyObject, Sendable {
    /// One observation of the magic acting on and known to `key`, or nil when
    /// this session runs no spellbook — a synthetic session with no SPEL index.
    func spellState(for key: ReferenceKey) -> PapyrusSpellState?

    /// Teaches `actor` one spell.
    ///
    /// - Returns: true when the spell was not already known, which is what
    ///   "True on success" means for an add that changes nothing.
    @discardableResult
    func addSpell(_ spell: ReferenceKey, to actor: ReferenceKey) -> Bool

    /// Forgets one spell, clearing any hand that was holding it.
    ///
    /// - Returns: true when the spell was known.
    @discardableResult
    func removeSpell(_ spell: ReferenceKey, from actor: ReferenceKey) -> Bool

    /// Readies `spell` in the hand `source` names, teaching it first when the
    /// actor does not know it.
    ///
    /// - Returns: false when there is no spellbook, when the record is not one
    ///   this load order carries, or when the spell's ETYP offers no such hand.
    @discardableResult
    func equipSpell(
        _ spell: ReferenceKey, source: CastingSource, on actor: ReferenceKey
    ) -> Bool

    /// Clears the hand `source` names, and only when it holds `spell`.
    ///
    /// - Returns: true when a hand was actually cleared.
    @discardableResult
    func unequipSpell(
        _ spell: ReferenceKey, source: CastingSource, on actor: ReferenceKey
    ) -> Bool

    /// Removes every effect on `actor` that came from `spell`.
    ///
    /// - Returns: how many effects were removed.
    @discardableResult
    func dispelSpell(_ spell: ReferenceKey, on actor: ReferenceKey) -> Int

    /// Removes every effect on `actor` that a dispel is allowed to touch.
    ///
    /// - Returns: how many effects were removed.
    @discardableResult
    func dispelAllSpells(on actor: ReferenceKey) -> Int

    /// Casts `spell` from `source` at once, optionally at a named target.
    ///
    /// - Returns: false when there is no caster runtime, when this load order
    ///   carries no such record, or when the source is not an actor the
    ///   session tracks values for.
    @discardableResult
    func castSpell(
        _ spell: ReferenceKey, from source: ReferenceKey, at target: ReferenceKey?
    ) -> Bool
}

/// Nonisolated hops for the magic operations, mirroring the rest of
/// `PapyrusWorldAccess`: one `MainActor.assumeIsolated` per method, which is an
/// assertion that natives run on the main actor rather than a suppression of
/// the check.
nonisolated extension PapyrusWorldAccess {
    func spellState(for key: ReferenceKey) -> PapyrusSpellState? {
        MainActor.assumeIsolated { bridge.spellState(for: key) }
    }

    @discardableResult
    func addSpell(_ spell: ReferenceKey, to actor: ReferenceKey) -> Bool {
        MainActor.assumeIsolated { bridge.addSpell(spell, to: actor) }
    }

    @discardableResult
    func removeSpell(_ spell: ReferenceKey, from actor: ReferenceKey) -> Bool {
        MainActor.assumeIsolated { bridge.removeSpell(spell, from: actor) }
    }

    @discardableResult
    func equipSpell(
        _ spell: ReferenceKey, source: CastingSource, on actor: ReferenceKey
    ) -> Bool {
        MainActor.assumeIsolated { bridge.equipSpell(spell, source: source, on: actor) }
    }

    @discardableResult
    func unequipSpell(
        _ spell: ReferenceKey, source: CastingSource, on actor: ReferenceKey
    ) -> Bool {
        MainActor.assumeIsolated { bridge.unequipSpell(spell, source: source, on: actor) }
    }

    @discardableResult
    func dispelSpell(_ spell: ReferenceKey, on actor: ReferenceKey) -> Int {
        MainActor.assumeIsolated { bridge.dispelSpell(spell, on: actor) }
    }

    @discardableResult
    func dispelAllSpells(on actor: ReferenceKey) -> Int {
        MainActor.assumeIsolated { bridge.dispelAllSpells(on: actor) }
    }

    @discardableResult
    func castSpell(
        _ spell: ReferenceKey, from source: ReferenceKey, at target: ReferenceKey?
    ) -> Bool {
        MainActor.assumeIsolated { bridge.castSpell(spell, from: source, at: target) }
    }
}
