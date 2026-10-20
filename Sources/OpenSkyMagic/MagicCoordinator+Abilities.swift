// The session side of carried effects: abilities reconciled against the
// spellbook, the entry lookup the per-second condition check reads, and the
// modifier rebuild for actors whose effects came back from a save.
// See docs/engine/magic.md and docs/engine/spellcasting.md.

import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyWorldState

extension MagicCoordinator {
    /// How often every resident actor's abilities are reconciled, so a spell a
    /// script added or removed takes effect without a hook on every path.
    public static let abilityReconcileSeconds: Float = 1

    /// Applies the abilities `holder` knows and removes the ones it forgot.
    @discardableResult
    public func reconcileAbilities(on holder: ActorValueHolder) -> AbilityReconcileReport {
        guard let caster else { return .none }
        let known = caster.knownAbilities(of: holder)
        return withEffects { runtime in
            SpellAbilityApplication.reconcile(known: known, on: holder, using: &runtime)
        } ?? .none
    }

    /// Runs `reconcileAbilities` over the resident actors once per interval, and
    /// rebuilds the modifiers of actors that came back from a save.
    func maintainCarriedEffects(delta: Float) {
        guard delta.isFinite, delta > 0 else { return }
        let holders = world.regeneratingHolders()
        rebuildLoadedModifiers(over: holders)
        abilityClock += delta
        guard abilityClock >= Self.abilityReconcileSeconds else { return }
        abilityClock = 0
        for holder in holders {
            reconcileAbilities(on: holder)
        }
    }

    /// Marks every actor other than the player that a load gave timed effects.
    /// `AVOV` keeps no temporary modifier, and an NPC has no holder until its
    /// cell streams in, so each one is rebuilt when it next becomes resident.
    public func noteEffectsRestored() {
        guard let store = effects?.store else { return }
        pendingModifierRebuild = Set(store.sortedDirtyKeys().filter { key in
            key != .player && store.component(ActiveEffectState.self, for: key)?.isEmpty == false
        })
        withEffects { $0.reestablishModifiers(on: .player) }
    }

    private func rebuildLoadedModifiers(over holders: [ActorValueHolder]) {
        guard !pendingModifierRebuild.isEmpty else { return }
        for holder in holders where pendingModifierRebuild.contains(holder.key) {
            pendingModifierRebuild.remove(holder.key)
            withEffects { $0.reestablishModifiers(on: holder) }
        }
    }

    // MARK: - Entry conditions

    /// The `CTDA` list of the entry `effect` came from, read again from its source.
    func entryConditions(of effect: ActiveEffect) -> ConditionList? {
        guard let entries = sourceEntries(of: effect.source) else { return nil }
        return entries.first { $0.effect?.id == effect.effect.resolvedID }?.item.conditions
    }

    /// The resolved effect list of a source record, where this session knows it.
    private func sourceEntries(of source: ActiveEffectSource) -> [ResolvedSpellEffect]? {
        guard let id = source.record.resolvedID else { return nil }
        switch source.kind {
        case .spell, .perk, .ability:
            return caster?.spellbook.spells.spell(id)?.effects
        case .enchantment:
            return enchantmentStore?.enchantment(id)?.effects
        case .potion, .ingredient:
            return nil
        }
    }
}

nonisolated extension ReferenceKey {
    /// The record a plugin key names, or nil for a placed or generated key.
    var resolvedID: ResolvedFormID? {
        guard case let .plugin(plugin, objectID) = self else { return nil }
        return ResolvedFormID(plugin: plugin, objectID: objectID)
    }
}
