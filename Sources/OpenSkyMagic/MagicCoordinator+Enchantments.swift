// Item enchantments: an equipped item's ENCH profile, a landed hit spending its
// charge, and worn constant effects going on and coming off. Melee and arrows
// share `applyWeaponEnchantment(_:)`. The worn reconcile is idempotent.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyWorldState

extension MagicCoordinator: WeaponEnchantmentApplying {
    @discardableResult
    public func applyWeaponEnchantment(_ hit: WeaponEnchantmentHit) -> WeaponEnchantmentReport? {
        guard let owner = world.actorValueHolder(for: hit.attacker) else { return nil }
        let holders = residentHolders(of: hit.targets)
        return withEffects { runtime in
            WeaponEnchantmentApplication.apply(hit, owner: owner, holders: holders, using: &runtime)
        }.flatMap(\.self)
    }

    /// Spends one dose of the poison on the striking weapon and applies the poison's
    /// effects to the target, scaled by its resistances like a hostile spell.
    @discardableResult
    public func applyWeaponPoison(_ hit: WeaponPoisonHit) -> WeaponPoisonReport? {
        guard
            let weapon = hit.weapon,
            let items = world.inventory?.baselines.items,
            let target = residentHolders(of: [SpellHitTarget(key: hit.target)])[hit.target]
        else { return nil }
        let plugin = pluginName
        return withEffects { runtime -> WeaponPoisonReport? in
            let poisons = runtime.store.component(WeaponPoisonState.self, for: hit.attacker)
            guard let poisons else { return nil }
            let (left, spent) = poisons.spendingDose(of: weapon)
            guard let spent, let potion = items.ingestibles[spent.rawValue] else { return nil }
            if left.isEmpty {
                runtime.store.reset(WeaponPoisonState.componentKind, for: hit.attacker)
            } else {
                runtime.store.set(left, for: hit.attacker)
            }
            let stored = Self.land(
                PoisonDose(potion: potion, id: spent, plugin: plugin),
                caster: hit.attacker, on: target, using: &runtime
            )
            return WeaponPoisonReport(
                poison: spent,
                dosesLeft: left.poisons[weapon]?.doses ?? 0,
                storedCount: stored
            )
        }.flatMap(\.self)
    }

    /// Applies `poison` straight to `target`, as a poison the Poisoned perk lets the
    /// player place in a pocket. Returns the timed effects stored, or nil.
    @discardableResult
    public func applyPlacedPoison(
        _ poison: FormID, by caster: ReferenceKey, on target: ReferenceKey
    ) -> Int? {
        guard
            let potion = world.inventory?.baselines.items.ingestibles[poison.rawValue],
            let holder = residentHolders(of: [SpellHitTarget(key: target)])[target]
        else { return nil }
        let plugin = pluginName
        return withEffects { runtime in
            Self.land(
                PoisonDose(potion: potion, id: poison, plugin: plugin),
                caster: caster, on: holder, using: &runtime
            )
        }
    }

    /// A poison's effects on `target`, scaled by its resistances like a hostile spell.
    private static func land(
        _ dose: PoisonDose, caster: ReferenceKey,
        on target: ActorValueHolder, using runtime: inout ActiveEffectRuntime
    ) -> Int {
        let (potion, id, plugin) = (dose.potion, dose.id, dose.plugin)
        let scaled = SpellHitApplication.scale(
            potion.effects, fromPlugin: plugin, ignoresResistance: false,
            on: target, using: runtime, resistances: .documentedDefaults
        )
        return runtime.apply(
            scaled.entries,
            fromPlugin: plugin,
            source: ActiveEffectSource(
                kind: .potion, record: runtime.sourceKey(of: id, fallbackPlugin: plugin)
            ),
            caster: caster,
            on: target
        ).count
    }
}

/// One poison and the plugin its effects resolve through.
private struct PoisonDose {
    let potion: Ingestible
    let id: FormID
    let plugin: String
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
        let items = world.inventory?.baselines.items
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
        if let caster, let values = world.actorValueHolder(for: holder.key) {
            caster.spellbook.releaseHands(wornBy: holder, on: values)
        }
        return refreshWornEnchantments(on: holder)
    }

    /// Brings `holder`'s worn constant effects in line with what it wears. An
    /// owner with no actor values, such as a container, changes nothing.
    @discardableResult
    public func refreshWornEnchantments(on holder: InventoryHolder) -> WornEnchantmentReport {
        guard
            let equipment = world.equipment,
            let values = world.actorValueHolder(for: holder.key)
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
