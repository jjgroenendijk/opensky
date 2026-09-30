// Session wiring for item enchantments: where an equipped item's ENCH comes
// from, how a landed hit spends its charge, and how a worn item's constant
// effects go on and come off. `applyWeaponEnchantment(_:)` serves both melee and
// projectiles. `refreshWornEnchantments(on:)` reconciles, so calling it twice
// changes nothing. The effect runtime is a value: it is taken out, changed,
// and put back.

import AppKit
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyWorld

/// Enchantment state the controller owns. Extensions cannot add stored
/// properties, so it lives as one value on `GameViewController`.
struct EnchantmentBridgeState {
    /// Load-order ENCH index, set by `wireEnchantments`. Nil without game data.
    /// Setting it drops every cached profile, because profiles derive from it.
    var store: EnchantmentStore? {
        didSet { profiles.invalidate() }
    }

    /// Resolved profiles, so the melee and archery frame hooks stop re-walking
    /// the records for an equipped set that has not changed.
    var profiles = ItemEnchantmentProfileCache()
    /// Human-readable result of the last panel or menu action.
    var lastActionText = "No enchantment action yet."
}

extension GameViewController: WeaponEnchantmentApplying {
    /// Spends an enchanted weapon's charge and applies its effects to what it hit.
    @discardableResult
    func applyWeaponEnchantment(_ hit: WeaponEnchantmentHit) -> WeaponEnchantmentReport? {
        guard
            var runtime = magicEffects.runtime,
            let owner = actorValueHolder(for: hit.attacker)
        else { return nil }
        let report = WeaponEnchantmentApplication.apply(
            hit,
            owner: owner,
            target: actorValueHolder(for: hit.target),
            using: &runtime
        )
        magicEffects.runtime = runtime
        return report
    }
}

extension GameViewController {
    /// Publishes the provider's ENCH index, so an equipped item can resolve its
    /// enchantment.
    ///
    /// Wired beside `wireMagicEffects`, which owns the effect runtime every
    /// application ultimately writes through.
    func wireEnchantments(provider: any WorldDataProviding) {
        enchantments.store = (provider as? MagicDataProviding)?.enchantmentStore
    }

    /// The resolved enchantment of one carried item, or nil when it has none or
    /// the session has no ENCH index. Cached after the first ask. The store is
    /// read before the call, because the call holds write access to
    /// `enchantments` and a read inside it would overlap.
    func enchantmentProfile(of item: FormID) -> ItemEnchantmentProfile? {
        let store = enchantments.store
        return enchantments.profiles.profile(of: item) { item in
            guard
                let store,
                let definition = worldItems.runtime?.inventory.baselines.items.definition(item)
            else { return nil }
            return ItemEnchantmentProfile.resolve(definition, using: store)
        }
    }

    /// What `item` has left on `holder`, or nil when it carries no enchantment.
    func enchantmentCharge(of item: FormID, on holder: ActorValueHolder) -> EnchantmentCharge? {
        guard
            let runtime = magicEffects.runtime,
            let profile = enchantmentProfile(of: item)
        else { return nil }
        return EnchantmentLedger(store: runtime.store).charge(of: profile, on: holder)
    }

    /// Brings `holder`'s worn constant effects in line with what it wears.
    /// Called after every equip and unequip, and once per actor after a load.
    /// An owner with no actor-value state, such as a container, answers
    /// "nothing changed".
    @discardableResult
    func refreshWornEnchantments(on holder: InventoryHolder) -> WornEnchantmentReport {
        guard
            var runtime = magicEffects.runtime,
            let equipment = worldItems.equipment,
            let values = actorValueHolder(for: holder.key)
        else { return .none }
        let worn = equipment.equipped(on: holder).compactMap { enchantmentProfile(of: $0) }
        let report = WornEnchantmentApplication.reconcile(
            worn: worn,
            on: values,
            using: &runtime
        )
        magicEffects.runtime = runtime
        return report
    }

    /// One item's enchantment and remaining charge, formatted, or nil when it has
    /// none. The one place a charge becomes words, so every readout agrees.
    /// Without a holder the item's full charge is reported.
    func enchantmentLine(of item: FormID, on holder: ActorValueHolder?) -> String? {
        guard let profile = enchantmentProfile(of: item) else { return nil }
        let charge = holder.flatMap { enchantmentCharge(of: item, on: $0) } ?? profile.fullCharge
        let shape = profile.isWorn ? "worn" : (profile.isStaff ? "staff" : "on hit")
        return "\(profile.name) (\(shape)): \(charge.describedLine)"
    }
}
