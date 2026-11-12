// The questions the active-effect runtime asks the world, set up once at load: what kind of
// source an effect came from, and which actors are undead.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyProgressionInterface

extension MagicCoordinator.ArchetypeLookups {
    /// Gives the runtime the lookups it cannot make itself.
    func prepareArchetypeLookups() {
        coordinator.withEffects { runtime in
            runtime.holderResolver = { [weak coordinator] key in
                coordinator?.world.actorValueHolder(for: key)
            }
            runtime.isUndead = { [weak coordinator] holder in
                coordinator?.world.actorHasKeyword(Self.undeadKeyword, on: holder) ?? false
            }
            runtime.sourceCategory = { [weak coordinator] source in
                coordinator?.archetypeLookups.category(of: source) ?? .other
            }
            runtime.entryConditions = { [weak coordinator] effect in
                coordinator?.abilityReconciler.entryConditions(of: effect)
            }
            runtime.worldRefusal = { [weak coordinator] archetype, holder in
                coordinator?.weaponArchetypes.worldRefusal(archetype, on: holder)
            }
            runtime.valueAndParts = coordinator.holdSettings.valueAndParts
        }
    }

    /// What kind of record `source` is, for Cure Disease and Cure Poison.
    func category(of source: ActiveEffectSource) -> ActiveEffectSourceCategory {
        switch source.kind {
        case .spell:
            coordinator.caster?.spellbook.spells.spell(key: source.record)?.spellType == .disease
                ? .disease : .other
        case .potion:
            isPoison(source.record) ? .poison : .other
        case .ingredient, .enchantment, .perk, .ability:
            .other
        }
    }

    /// Whether `record` is an `ALCH` with the Poison flag.
    func isPoison(_ record: ReferenceKey) -> Bool {
        guard
            case let .plugin(plugin, objectID) = record,
            let items = coordinator.world.inventory?.baselines.items,
            let id = coordinator.effects?.effects.loadOrderFormID(
                ResolvedFormID(plugin: plugin, objectID: objectID)
            )
        else { return false }
        return items.ingestibles[id.rawValue]?.flags.contains(.poison) == true
    }

    /// The keyword Turn Undead requires on its target.
    static let undeadKeyword = "ActorTypeUndead"
}
