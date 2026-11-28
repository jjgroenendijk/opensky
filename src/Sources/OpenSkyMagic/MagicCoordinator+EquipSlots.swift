// What an item in a casting slot gives while it is there: each effect's equip ability,
// and on a readied enchanted weapon the main effect's enchant shader and art. See
// docs/formats/magic-records.md#mgef-data.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface

extension MagicCoordinator.WeaponEnchantments {
    /// Matches equip abilities for the player and every caster, and each resident's weapon
    /// look. An actor whose slots did not change since the last frame costs one compare.
    func advanceEquipSlots(playerWeaponsDrawn: Bool?) {
        let actors = Set([ReferenceKey.player] + (coordinator.caster?.castingActors ?? []))
        for key in actors.sorted() {
            guard let holder = coordinator.world.actorValueHolder(for: key) else { continue }
            let slots = slotKeys(of: holder)
            if coordinator.castingState.equipSlots[key] != slots {
                reconcileEquipAbilities(on: holder)
            }
        }
        let residents = Set([ReferenceKey.player] + coordinator.world.residentActorKeys())
            .union(coordinator.castingState.weaponEnchantVisuals.keys)
        for key in residents.sorted() {
            let drawn = key == .player
                ? playerWeaponsDrawn == true : coordinator.world.weaponsDrawn(of: key)
            showWeaponEnchant(drawn ? weaponEnchantVisual(of: key) : nil, on: key)
        }
    }

    /// Casts and dispels `holder`'s equip abilities to match its casting slots.
    func reconcileEquipAbilities(on holder: ActorValueHolder) {
        guard let spells = coordinator.caster?.spellbook.spells else { return }
        coordinator.castingState.equipSlots[holder.key] = slotKeys(of: holder)
        let slotted = slottedEffects(of: holder)
        coordinator.withEffects { runtime in
            EquipAbilityApplication.reconcile(
                slotted: slotted, on: holder, spells: spells, using: &runtime
            )
        }
    }

    /// The spells in the hands and the equipped items with a cast enchantment.
    private func slotKeys(of holder: ActorValueHolder) -> [ReferenceKey] {
        let hands = SpellHand.allCases.compactMap {
            coordinator.caster?.spellbook.state(of: holder).spell(in: $0)
        }
        return hands + castItems(of: holder).map(\.enchantment)
    }

    private func castItems(of holder: ActorValueHolder) -> [ItemEnchantmentProfile] {
        let owner = InventoryHolder(actor: holder)
        return (coordinator.world.equipment?.equipped(on: owner) ?? []).compactMap {
            enchantmentProfile(of: $0, on: owner)
        }.filter { !$0.isWorn }
    }

    private func slottedEffects(of holder: ActorValueHolder) -> [ResolvedMagicEffect] {
        let spellbook = coordinator.caster?.spellbook
        let hands = SpellHand.allCases.compactMap { hand in
            spellbook?.state(of: holder).spell(in: hand)
                .flatMap { spellbook?.spells.spell(key: $0) }
        }.flatMap { $0.effects.compactMap(\.effect) }
        let items = castItems(of: holder).flatMap(resolvedEffects).compactMap(\.effect)
        return hands + items
    }

    private func resolvedEffects(of profile: ItemEnchantmentProfile) -> [ResolvedSpellEffect] {
        guard let store = coordinator.effects?.effects else { return [] }
        return profile.parts.flatMap {
            store.resolvedEffects(
                $0.entries,
                fromPlugin: $0.plugin,
                castingType: profile.castingType
            )
        }
    }

    /// The first held weapon's enchantment look: a cast enchantment with a use left.
    func weaponEnchantVisual(of key: ReferenceKey) -> WeaponEnchantVisual? {
        guard
            let holder = coordinator.world.actorValueHolder(for: key),
            let items = coordinator.world.inventory?.baselines.items
        else { return nil }
        for profile in castItems(of: holder) where items.weapon(profile.item) != nil {
            let charge = enchantmentCharge(of: profile.item, on: holder)
            if let charge, charge.capacity > 0, charge.remaining < charge.costPerUse {
                continue
            }
            let effects = resolvedEffects(of: profile)
            guard
                let main = MainMagicEffect.index(of: effects, concentration: false),
                let effect = effects[main].effect,
                let data = effect.effect.data
            else { continue }
            return data.enchantVisuals != nil
                ? WeaponEnchantVisual(
                    plugin: effect.sourcePlugin, shader: nil, art: nil, visuals: data.enchantVisuals
                )
                : WeaponEnchantVisual(
                    plugin: effect.sourcePlugin, shader: data.enchantShader, art: data.enchantArt
                )
        }
        return nil
    }

    private func showWeaponEnchant(_ wanted: WeaponEnchantVisual?, on key: ReferenceKey) {
        let shown = coordinator.castingState.weaponEnchantVisuals[key]
        guard shown != wanted else { return }
        if let shown {
            coordinator.pendingCommands.append(.weaponEnchantVisual(
                shown,
                actor: key,
                shown: false
            ))
        }
        if let wanted {
            coordinator.pendingCommands.append(.weaponEnchantVisual(
                wanted,
                actor: key,
                shown: true
            ))
        }
        coordinator.castingState.weaponEnchantVisuals[key] = wanted
    }
}
