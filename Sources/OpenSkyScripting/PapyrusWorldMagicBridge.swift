// The magic half of the native-to-world seam. `spellState(for:)` returns one
// observation, so related reads cannot straddle a write. Learning goes through
// `SpellbookRuntime`, dispelling through `ActiveEffectRuntime`, and
// `Spell.Cast` through `CasterRuntime`. See docs/engine/papyrus-spell-natives.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyMagicInterface

/// One actor's magic as a Papyrus native sees it.
nonisolated public struct PapyrusSpellState: Equatable, Sendable {
    /// SPEL and SCRL records this actor knows.
    public let knownSpells: Set<ReferenceKey>
    /// The MGEF behind every effect currently acting on this actor.
    public let activeEffects: Set<ReferenceKey>
    /// Every keyword those effects carry, resolved once so
    /// `HasMagicEffectWithKeyword` is a set membership test rather than a walk
    /// back through the record store.
    public let effectKeywords: Set<ReferenceKey>
    /// The spell readied in each hand, absent for a hand holding none.
    public let handSpells: [SpellHand: ReferenceKey]

    public init(
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
@MainActor
public protocol PapyrusWorldMagicBridge: AnyObject, Sendable {
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
