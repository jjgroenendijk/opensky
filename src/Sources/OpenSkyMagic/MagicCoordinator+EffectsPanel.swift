// The Magic Effects readout: the effects running on the player and the nearest actor, and
// the actions that consume an item or dispel them. Each action returns the line it shows.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface

extension MagicCoordinator.EffectsPanel {
    var magicEffectControlSnapshot: MagicEffectControlSnapshot {
        guard let runtime = coordinator.effects else { return .unavailable }
        let nearest = coordinator.world.nearestActorValueHolder()
        var snapshot = MagicEffectControlSnapshot(
            isAvailable: true,
            playerEffects: runtime.active(on: .player).map { readout(of: $0, runtime: runtime) },
            nearestActorName: nearest.map { coordinator.world.actorName($0) }
        )
        snapshot.playerInfluence = runtime.influence(on: .player)
        snapshot.nearestActorInfluence = nearest.map { runtime.influence(on: $0) } ?? .none
        return snapshot
    }

    @discardableResult
    func consumeFirstCarriedMagicItem() -> MagicEffectActionOutcome {
        guard coordinator.effects != nil else { return coordinator.recordEffect(.unavailable) }
        let item = coordinator
            .itemUse.carriedItems { items, item in items.magicItemUse(item) == nil ? nil : item }
            .first
        guard let item else { return coordinator.recordEffect(.nothingToConsume) }
        return coordinator.itemUse.consumeMagicItem(item)
    }

    @discardableResult
    func dispelPlayerMagicEffects() -> MagicEffectActionOutcome {
        guard let removed = coordinator.withEffects({ $0.dispelAll(on: .player) }) else {
            return coordinator.recordEffect(.unavailable)
        }
        return coordinator.recordEffect(.dispelled(removed: removed))
    }

    func readout(
        of effect: ActiveEffect,
        runtime: ActiveEffectRuntime
    ) -> ActiveEffectReadout {
        var readout = ActiveEffectReadout(
            name: effectName(effect.effect, runtime: runtime),
            sourceName: sourceName(effect.source.kind),
            mode: effect.mode,
            isDetrimental: effect.isDetrimental,
            magnitude: effect.values.first?.magnitude ?? 0,
            duration: effect.duration,
            remaining: effect.remaining,
            valueNames: effect.values
                .filter { ActorValueIdentity.isVanilla(index: $0.index) }
                .map { ActorValueIdentity.description(of: $0.index) },
            archetype: archetypeText(of: effect, runtime: runtime)
        )
        if effect.duration > 0 {
            readout.timeLeftText = coordinator.texts.magic.timeLeft(effect.remaining)
        }
        return readout
    }

    /// The archetype and what it does, such as "light: carries a light".
    func archetypeText(of effect: ActiveEffect, runtime: ActiveEffectRuntime) -> String {
        guard let archetype = runtime.effects.effect(key: effect.effect)?.effect.data?.archetype
        else { return "unknown" }
        guard let rule = MagicArchetypeRule.rule(for: archetype) else {
            return archetype.description
        }
        return "\(archetype.description): \(rule.summary)"
    }

    func sourceName(_ kind: ActiveEffectSourceKind) -> String {
        let setting: String? = switch kind {
        case .potion: "sMagicTypePotion"
        case .ingredient: "sIngredient"
        case .spell: "sMagicTypeSpell"
        case .enchantment: "sMagicTypeEnchantment"
        case .ability: "sMagicTypeAbility"
        case .perk: nil
        }
        return setting.map { coordinator.texts.magic.word($0, or: kind.describedName) } ?? kind
            .describedName
    }

    /// Falls back to the key, so a line names something even when the record
    /// left the load order.
    func effectName(_ key: ReferenceKey, runtime: ActiveEffectRuntime) -> String {
        guard case let .plugin(name, objectID) = key else { return key.description }
        let resolved = ResolvedFormID(plugin: name, objectID: objectID)
        return runtime.effects.effect(resolved)?.displayName ?? key.description
    }
}
