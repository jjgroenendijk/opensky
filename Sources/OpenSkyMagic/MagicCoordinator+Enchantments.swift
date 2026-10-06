// Item enchantments: an equipped item's ENCH profile, a landed hit spending its
// charge, and worn constant effects going on and coming off. Melee and arrows
// share `applyWeaponEnchantment(_:)`. The worn reconcile is idempotent.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface

extension MagicCoordinator: WeaponEnchantmentApplying {
    @discardableResult
    public func applyWeaponEnchantment(_ hit: WeaponEnchantmentHit) -> WeaponEnchantmentReport? {
        guard let owner = world?.actorValueHolder(for: hit.attacker) else { return nil }
        let target = world?.actorValueHolder(for: hit.target)
        return withEffects { runtime in
            WeaponEnchantmentApplication.apply(hit, owner: owner, target: target, using: &runtime)
        }.flatMap(\.self)
    }
}

extension MagicCoordinator {
    /// What the inventory panel shows about the profile cache.
    public var enchantmentCacheReadout: EnchantmentCacheReadout {
        profiles.readout
    }

    /// One carried item's enchantment, or nil when it has none or the session
    /// has no ENCH index. Cached after the first ask.
    public func enchantmentProfile(of item: FormID) -> ItemEnchantmentProfile? {
        let store = enchantmentStore
        let items = world?.inventory?.baselines.items
        return profiles.profile(of: item) { item in
            guard let store, let definition = items?.definition(item) else { return nil }
            return ItemEnchantmentProfile.resolve(definition, using: store)
        }
    }

    /// What `item` has left on `holder`, or nil when it carries no enchantment.
    public func enchantmentCharge(
        of item: FormID,
        on holder: ActorValueHolder
    ) -> EnchantmentCharge? {
        guard let runtime = effects, let profile = enchantmentProfile(of: item) else { return nil }
        return EnchantmentLedger(store: runtime.store).charge(of: profile, on: holder)
    }

    /// Brings magic in line after `holder`'s worn set changed: readied spells
    /// leave the hands a worn item holds, then worn enchantments are re-read.
    @discardableResult
    public func equipmentChanged(on holder: InventoryHolder) -> WornEnchantmentReport {
        if let caster, let values = world?.actorValueHolder(for: holder.key) {
            caster.spellbook.releaseHands(wornBy: holder, on: values)
        }
        return refreshWornEnchantments(on: holder)
    }

    /// Brings `holder`'s worn constant effects in line with what it wears. An
    /// owner with no actor values, such as a container, changes nothing.
    @discardableResult
    public func refreshWornEnchantments(on holder: InventoryHolder) -> WornEnchantmentReport {
        guard
            let equipment = world?.equipment,
            let values = world?.actorValueHolder(for: holder.key)
        else { return .none }
        let worn = equipment.equipped(on: holder).compactMap { enchantmentProfile(of: $0) }
        return withEffects { runtime in
            WornEnchantmentApplication.reconcile(worn: worn, on: values, using: &runtime)
        } ?? .none
    }

    /// One item's enchantment and charge as words, so every readout agrees.
    /// Without a holder the full charge is reported.
    public func enchantmentLine(of item: FormID, on holder: ActorValueHolder?) -> String? {
        guard let profile = enchantmentProfile(of: item) else { return nil }
        let charge = holder.flatMap { enchantmentCharge(of: item, on: $0) } ?? profile.fullCharge
        let shape = profile.isWorn ? "worn" : (profile.isStaff ? "staff" : "on hit")
        return "\(profile.name) (\(shape)): \(charge.describedLine)"
    }
}
