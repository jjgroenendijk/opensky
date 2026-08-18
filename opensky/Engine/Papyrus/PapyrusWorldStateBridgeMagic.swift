// `PapyrusWorldMagicBridge` conformance (issue #474, roadmap item 19.11): where
// the spell natives meet 19.6's active effects and 19.7's spellbook and cast
// loop.
//
// Split out of `PapyrusWorldStateBridge.swift` for the reason the quest and
// actor halves are: that file is already at its size shape, and a reader
// chasing "what does `AddSpell` really do" should land on one screen that says
// so.
//
// ## Why the collaborators are closures
//
// The caster runtime is built by `wireCasting` and the active-effect runtime by
// `wireMagicEffects`, and the order those steps run in is the controller's
// business rather than this bridge's — the same reason the actor-value and
// ragdoll runtimes arrive as closures. The active-effect one is a *mutating*
// closure rather than a getter because `ActiveEffectRuntime` is a struct the
// session owns by value: handing out a copy to dispel through would grow a
// tally nothing ever reads and drop the write on the floor.
//
// Documented in docs/engine/papyrus-vm.md and docs/engine/magic.md.

import Foundation
import simd

extension PapyrusWorldStateBridge {
    // MARK: - Reading

    func spellState(for key: ReferenceKey) -> PapyrusSpellState? {
        guard
            let caster = casterRuntime?(),
            let holder = actorHolder(for: key)
        else { return nil }
        let spellbook = caster.spellbook.state(of: holder)
        let effects = worldState.component(ActiveEffectState.self, for: key)
        let active = effects?.effects ?? []
        return PapyrusSpellState(
            knownSpells: Set(spellbook.known),
            activeEffects: Set(active.map(\.effect)),
            effectKeywords: effectKeywords(of: active),
            handSpells: SpellHand.allCases.reduce(into: [:]) { table, hand in
                table[hand] = spellbook.spell(in: hand)
            }
        )
    }

    // MARK: - Knowing

    @discardableResult
    func addSpell(_ spell: ReferenceKey, to actor: ReferenceKey) -> Bool {
        guard let caster = casterRuntime?(), let holder = actorHolder(for: actor) else {
            return false
        }
        return caster.spellbook.learn(spell, on: holder)
    }

    @discardableResult
    func removeSpell(_ spell: ReferenceKey, from actor: ReferenceKey) -> Bool {
        guard let caster = casterRuntime?(), let holder = actorHolder(for: actor) else {
            return false
        }
        return caster.spellbook.forget(spell, on: holder)
    }

    // MARK: - Readying

    @discardableResult
    func equipSpell(
        _ spell: ReferenceKey, source: CastingSource, on actor: ReferenceKey
    ) -> Bool {
        guard
            let caster = casterRuntime?(),
            let holder = actorHolder(for: actor),
            let hand = source.hand
        else { return false }
        // "If the calling actor does not have akSpell, it will be given to
        // them." (<https://ck.uesp.net/wiki/EquipSpell_-_Actor>) The learn is
        // therefore part of the equip rather than a caller's responsibility.
        caster.spellbook.learn(spell, on: holder)
        return (try? caster.spellbook.equip(spell, in: hand, on: holder)) != nil
    }

    @discardableResult
    func unequipSpell(
        _ spell: ReferenceKey, source: CastingSource, on actor: ReferenceKey
    ) -> Bool {
        guard
            let caster = casterRuntime?(),
            let holder = actorHolder(for: actor),
            let hand = source.hand,
            caster.spellbook.state(of: holder).spell(in: hand) == spell
        else { return false }
        return caster.spellbook.unequip(hand, on: holder) != nil
    }

    // MARK: - Dispelling

    @discardableResult
    func dispelSpell(_ spell: ReferenceKey, on actor: ReferenceKey) -> Int {
        guard let holder = actorHolder(for: actor) else { return 0 }
        return dispelEffects?(holder) { $0.source.record == spell } ?? 0
    }

    @discardableResult
    func dispelAllSpells(on actor: ReferenceKey) -> Int {
        guard let holder = actorHolder(for: actor) else { return 0 }
        let spells = casterRuntime?()?.spellbook.spells
        return dispelEffects?(holder) { effect in
            Self.isDispellable(effect, spells: spells)
        } ?? 0
    }

    /// Whether `DispelAllSpells` is allowed to remove one effect.
    ///
    /// "Will dispel all spells affecting this actor with the exception of
    /// Abilities, Diseases, worn or constant effect enchantments, or
    /// addictions." (<https://ck.uesp.net/wiki/DispelAllSpells_-_Actor>) Three
    /// of the five exceptions are SPIT spell types and read straight off the
    /// record; the other two are the constant mode and the enchantment source
    /// kind, which is what a worn enchantment's effect carries.
    ///
    /// A source record this load order no longer resolves is left alone, which
    /// keeps a dropped plugin from turning into a silent mass dispel.
    static func isDispellable(_ effect: ActiveEffect, spells: SpellStore?) -> Bool {
        guard effect.source.kind == .spell, !effect.isConstant else { return false }
        guard let record = spells?.spell(key: effect.source.record) else { return false }
        switch record.spellType {
        case .ability, .disease, .addiction: return false
        default: return true
        }
    }

    // MARK: - Casting

    @discardableResult
    func castSpell(
        _ spell: ReferenceKey, from source: ReferenceKey, at target: ReferenceKey?
    ) -> Bool {
        guard
            let caster = casterRuntime?(),
            let record = caster.spellbook.record(spell),
            let holder = actorHolder(for: source)
        else { return false }
        guard
            let target,
            target != source,
            record.data?.delivery != .selfTarget
        else {
            _ = caster.apply(record, caster: holder)
            return true
        }
        return castAtNamedTarget(record, caster: holder, target: target)
    }

    /// Applies a cast whose script named the target outright.
    ///
    /// The aim ray the caster runtime normally uses answers "what is the caster
    /// pointing at", and a script that named a target is not pointing at
    /// anything — the wiki is explicit that this cast "will be cast even if the
    /// actor's hands are not readied"
    /// (<https://ck.uesp.net/wiki/Cast_-_Spell>). So the payload is handed to
    /// the same `SpellHitApplying` seam a projectile's landing uses, with the
    /// named actor as the one direct target and no area sweep: nothing here
    /// knows where the impact was, and inventing a position would catch
    /// bystanders a real cast might not.
    private func castAtNamedTarget(
        _ record: ResolvedSpell,
        caster holder: ActorValueHolder,
        target: ReferenceKey
    ) -> Bool {
        guard let apply = applySpellHit else { return false }
        let payload = record.payload(caster: holder.key)
        _ = apply(SpellHit(
            payload: payload,
            position: SIMD3<Float>(),
            targets: [SpellHitTarget(key: target)]
        ))
        return true
    }

    /// Every keyword the MGEFs behind `effects` carry, resolved once.
    private func effectKeywords(of effects: [ActiveEffect]) -> Set<ReferenceKey> {
        guard let store = magicEffectStore else { return [] }
        return effects.reduce(into: []) { keywords, effect in
            guard let record = store.effect(key: effect.effect) else { return }
            keywords.formUnion(record.keywordKeys(in: store))
        }
    }
}
