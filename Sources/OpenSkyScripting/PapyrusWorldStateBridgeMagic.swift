// `PapyrusWorldMagicBridge` conformance: spell natives meet active effects, the
// spellbook, and the cast loop. Collaborators are closures. The active-effect
// one is mutating, because the session owns that struct by value.
// See docs/engine/papyrus-spell-natives.md and docs/engine/spellcasting.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyWorldState
import simd

extension PapyrusWorldStateBridge {
    // MARK: - Reading

    public func spellState(for key: ReferenceKey) -> PapyrusSpellState? {
        guard
            let caster = casterRuntime?(),
            let holder = actorHolder(for: key)
        else { return nil }
        let spellbook = caster.spellbookAccess.state(of: holder)
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
    public func addSpell(_ spell: ReferenceKey, to actor: ReferenceKey) -> Bool {
        guard let caster = casterRuntime?(), let holder = actorHolder(for: actor) else {
            return false
        }
        return caster.spellbookAccess.learn(spell, on: holder)
    }

    @discardableResult
    public func removeSpell(_ spell: ReferenceKey, from actor: ReferenceKey) -> Bool {
        guard let caster = casterRuntime?(), let holder = actorHolder(for: actor) else {
            return false
        }
        return caster.spellbookAccess.forget(spell, on: holder)
    }

    // MARK: - Readying

    @discardableResult
    public func equipSpell(
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
        caster.spellbookAccess.learn(spell, on: holder)
        return (try? caster.spellbookAccess.equip(spell, in: hand, on: holder)) != nil
    }

    @discardableResult
    public func unequipSpell(
        _ spell: ReferenceKey, source: CastingSource, on actor: ReferenceKey
    ) -> Bool {
        guard
            let caster = casterRuntime?(),
            let holder = actorHolder(for: actor),
            let hand = source.hand,
            caster.spellbookAccess.state(of: holder).spell(in: hand) == spell
        else { return false }
        return caster.spellbookAccess.unequip(hand, on: holder) != nil
    }

    // MARK: - Dispelling

    @discardableResult
    public func dispelSpell(_ spell: ReferenceKey, on actor: ReferenceKey) -> Int {
        guard let holder = actorHolder(for: actor) else { return 0 }
        return dispelEffects?(holder) { $0.source.record == spell } ?? 0
    }

    @discardableResult
    public func dispelAllSpells(on actor: ReferenceKey) -> Int {
        guard let holder = actorHolder(for: actor) else { return 0 }
        let spells = casterRuntime?()?.spellbookAccess.spells
        return dispelEffects?(holder) { effect in
            Self.isDispellable(effect, spells: spells)
        } ?? 0
    }

    /// Whether `DispelAllSpells` may remove one effect. It spares abilities,
    /// diseases, worn or constant enchantments, and addictions
    /// (<https://ck.uesp.net/wiki/DispelAllSpells_-_Actor>). An unresolved source
    /// record is left alone.
    public static func isDispellable(_ effect: ActiveEffect, spells: SpellStore?) -> Bool {
        guard effect.source.kind == .spell, !effect.isConstant else { return false }
        guard let record = spells?.spell(key: effect.source.record) else { return false }
        switch record.spellType {
        case .ability, .disease, .addiction: return false
        default: return true
        }
    }

    // MARK: - Casting

    @discardableResult
    public func castSpell(
        _ spell: ReferenceKey, from source: ReferenceKey, at target: ReferenceKey?
    ) -> Bool {
        guard
            let caster = casterRuntime?(),
            let record = caster.spellbookAccess.record(spell),
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

    /// Applies a cast whose script named the target. It skips the aim ray and hands
    /// the payload to `SpellHitApplying` with the named actor as the only target
    /// (<https://ck.uesp.net/wiki/Cast_-_Spell>). No area sweep, since no impact
    /// position is known.
    private func castAtNamedTarget(
        _ record: ResolvedSpell,
        caster holder: ActorValueHolder,
        target: ReferenceKey
    ) -> Bool {
        guard let apply = applySpellHit else { return false }
        let payload = record.payload(caster: holder.key)
        _ = apply(SpellHit(
            payload: payload,
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
