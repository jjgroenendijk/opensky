// Magic items and spell lists: consuming a potion or scroll, granting authored spells, and
// dispelling.

import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
public import OpenSkyMagicInterface
import OpenSkyPhysics
public import OpenSkyProgressionInterface
import OpenSkyWorldState

extension MagicCoordinator.ItemUse {
    /// - Returns: how many effects were removed.
    public func dispelEffects(
        on holder: ActorValueHolder, where predicate: (ActiveEffect) -> Bool
    ) -> Int {
        coordinator.withEffects { $0.dispel(on: holder, where: predicate) } ?? 0
    }

    /// Adds and removes the abilities the actor's perks grant. False when no caster or
    /// effect runtime is wired.
    @discardableResult
    public func reconcilePerkAbilities(on holder: ActorValueHolder, perks: any PerkAccess) -> Bool {
        guard let spells = coordinator.caster?.spellbook.spells else { return false }
        return coordinator.withEffects { effects in
            _ = PerkAbilityApplication.reconcile(
                on: holder, perks: perks, spells: spells, using: &effects
            )
        } != nil
    }
}

extension MagicCoordinator.ItemUse {
    /// Consumes `item` from the player and applies it to the player. The menu
    /// and the readout both call this, and show the line of the outcome it returns.
    @discardableResult
    public func consumeMagicItem(_ item: FormID) -> MagicEffectActionOutcome {
        guard coordinator.effects != nil, let inventory = coordinator.world.inventory else {
            return coordinator.recordEffect(.unavailable)
        }
        let name = inventory.baselines.items.definition(item)?.editorID ?? item.description
        do {
            let plugin = coordinator.pluginName
            let outcome = try coordinator.withEffects { runtime in
                try runtime.consume(
                    item, use: (.player, .player), inventory: inventory, fromPlugin: plugin
                ) { entries, source in
                    coordinator.perkEffects.perkScaledPotion(
                        entries, of: source, fromPlugin: plugin, drinker: .player
                    )
                }
            }
            if outcome?.kind == .ingredient {
                coordinator.world.playerAteIngredient(item)
            }
            return coordinator.recordEffect(.consumed(item: name, outcome))
        } catch {
            return coordinator.recordEffect(.consumeFailed(
                item: name,
                reason: String(describing: error)
            ))
        }
    }

    /// Grants `holder`'s authored spell list on first ask, so townsfolk who
    /// never fight write no spellbook into the save.
    public func grantAuthoredSpells(to holder: ActorValueHolder) {
        guard
            let caster = coordinator.caster,
            let spellBaselines = coordinator.spellBaselines,
            let spellPluginName = coordinator.spellPluginName,
            !coordinator.grantedActors.contains(holder.key)
        else { return }
        coordinator.grantedActors.insert(holder.key)
        let roll = spellBaselines.templates.leveling.roll(
            of: holder, frozenLevel: caster.spellbook.store.frozenLeveledLevel(of: holder.key)
        )
        let baseline = spellBaselines.baseline(for: holder.subject, roll: roll)
        caster.spellbook.grant(
            caster.spellbook.resolve(baseline.all, fromPlugin: spellPluginName),
            to: holder
        )
        coordinator.abilityReconciler.reconcileAbilities(on: holder)
    }

    /// The carried items, in FormID order, that `transform` maps to a value.
    func carriedItems<Value>(_ transform: (ItemDefinitionStore, FormID) -> Value?) -> [Value] {
        guard let inventory = coordinator.world.inventory else { return [] }
        let items = inventory.baselines.items
        return inventory.inventory(of: .player).stacks
            .map(\.item)
            .sorted { $0.rawValue < $1.rawValue }
            .compactMap { transform(items, $0) }
    }

    /// Whether `hand` holds a readied spell, which routes its button to the
    /// cast loop instead of to melee.
    public func hasReadiedSpell(in hand: SpellHand) -> Bool {
        coordinator.caster?.spellbook.state(of: .player).spell(in: hand) != nil
    }
}
