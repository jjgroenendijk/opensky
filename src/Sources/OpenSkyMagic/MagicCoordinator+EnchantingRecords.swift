// The enchanting state saved on the player: disenchanting teaches a base, and each made item
// keeps its profile. See docs/engine/enchanting.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyProgressionInterface
import OpenSkyWorldState

extension MagicCoordinator.EnchantingRecords {
    /// Destroys one `item` and teaches the root of its enchantment's base chain.
    @discardableResult
    func disenchant(_ item: FormID) -> EnchantingOutcome {
        guard
            let store = coordinator.enchantmentStore,
            let inventory = coordinator.world.inventory
        else {
            return noteEnchanting(.unavailable)
        }
        guard inventory.count(of: item, in: .player) > 0 else {
            return noteEnchanting(.refused(.notCarried))
        }
        guard
            let profile = coordinator.weaponEnchantments.enchantmentProfile(of: item),
            let base = rootBase(of: profile),
            let root = store.enchantment(key: base)
        else { return noteEnchanting(.refused(.notEnchanted)) }
        guard !profile.isStaff, !coordinator.world.itemHasKeyword(
            "MagicDisallowEnchanting",
            on: item
        ) else {
            return noteEnchanting(.refused(.cannotDisenchant))
        }
        let state = enchantingState
        guard !state.knows(base) else { return noteEnchanting(.refused(.alreadyKnown)) }
        let items = inventory.baselines.items
        let worth = items.gameValue(of: item) - (items.definition(item)?.value ?? 0)
        let itemName = coordinator.world.itemName(item)
        _ = attempt { try inventory.remove(item, count: 1, from: .player) }
        writeEnchanting(state.learning(base))
        reportEnchantingUse(coordinator.rules.enchanting.disenchantExperience(worth: worth))
        return noteEnchanting(.learned(item: itemName, base: root.displayName))
    }

    var enchantingState: EnchantingState {
        coordinator.effects?.store
            .component(EnchantingState.self, for: .player) ?? EnchantingState()
    }

    /// The profile of the made enchantment on `holder`'s best copy of `item`, or nil.
    func madeProfile(of item: FormID, on holder: InventoryHolder) -> ItemEnchantmentProfile? {
        guard
            let store = coordinator.enchantmentStore,
            let id = coordinator.world.inventory?.copies(of: item, in: holder).first?.enchantment,
            EnchantingState.isMade(id),
            let made = enchantingState.made[id]
        else { return nil }
        let wielder = coordinator.world.actorValueHolder(for: holder.key)
        return ItemEnchantmentProfile.made(
            made, item: item, using: store,
            skill: wielder.map(coordinator.enchantingTable.enchantingSkill(of:)) ?? 0
        )
    }

    /// The last link of `profile`'s base chain, which disenchanting teaches.
    func rootBase(of profile: ItemEnchantmentProfile) -> ReferenceKey? {
        guard
            let store = coordinator.enchantmentStore,
            case let .plugin(name, objectID) = profile.enchantment,
            let root = store.baseChain(of: ResolvedFormID(plugin: name, objectID: objectID)).last
        else { return nil }
        return ReferenceKey(resolved: root.id)
    }

    func reportEnchantingUse(_ amount: Float) {
        guard amount > 0, let skill = ActorValueIdentity.index(named: "Enchanting") else { return }
        coordinator.world.reportSkillUse(SkillUseEvent(
            actor: .player,
            action: .craft(skill: skill),
            amount: amount
        ))
    }

    func writeEnchanting(_ state: EnchantingState) {
        guard let store = coordinator.effects?.store else { return }
        if state.isEmpty {
            store.reset(.enchanting, for: .player)
        } else {
            store.set(state, for: .player)
        }
    }

    @discardableResult
    func noteEnchanting(_ outcome: EnchantingOutcome) -> EnchantingOutcome {
        coordinator.enchantingMemory.lastEnchanting = outcome
        return outcome
    }
}
