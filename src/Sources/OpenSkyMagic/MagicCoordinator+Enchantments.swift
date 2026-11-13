// Item enchantments: an equipped item's ENCH profile, a landed hit spending its
// charge, and worn constant effects going on and coming off. Melee and arrows
// share `applyWeaponEnchantment(_:)`. The worn reconcile is idempotent.

public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface
public import OpenSkyMagicInterface
import OpenSkyWorldState

extension MagicCoordinator.WeaponEnchantments {
    @discardableResult
    public func applyWeaponEnchantment(_ hit: WeaponEnchantmentHit) -> WeaponEnchantmentReport? {
        let owner = coordinator.world.actorValueHolder(for: hit.attacker)
        let holders = coordinator.casterBridge.residentHolders(of: hit.targets)
        let inventory = coordinator.world.inventory
        let report = coordinator.withEffects { runtime in
            WeaponEnchantmentApplication.apply(
                hit, owner: owner, holders: holders, using: &runtime, inventory: inventory
            )
        }.flatMap(\.self)
        if let notice = CastNoticeText.notice(after: report, by: hit.attacker) {
            coordinator.pendingCommands.append(.notice(coordinator.texts.castNotices[notice]))
        }
        return report
    }

    /// Spends one dose of the poison on the striking weapon and applies the poison's
    /// effects to the target, scaled by its resistances like a hostile spell.
    public func applyWeaponPoison(_ hit: WeaponPoisonHit) {
        guard
            let weapon = hit.weapon,
            let items = coordinator.world.inventory?.baselines.items,
            let target = coordinator.casterBridge
                .residentHolders(of: [SpellHitTarget(key: hit.target)])[hit.target]
        else { return }
        let plugin = coordinator.pluginName
        let landed = coordinator.withEffects { runtime -> Bool in
            let poisons = runtime.store.component(WeaponPoisonState.self, for: hit.attacker)
            guard let poisons else { return false }
            let (left, spent) = poisons.spendingDose(of: weapon)
            guard let spent, let potion = items.ingestibles[spent.rawValue] else { return false }
            if left.isEmpty {
                runtime.store.reset(WeaponPoisonState.componentKind, for: hit.attacker)
            } else {
                runtime.store.set(left, for: hit.attacker)
            }
            _ = MagicCoordinator.PoisonDoses.land(
                PoisonDose(potion: potion, id: spent, plugin: plugin),
                caster: hit.attacker, on: target, using: &runtime
            )
            return runtime.lastApplication.landed > 0
        }
        if landed == true, hit.target == .player {
            coordinator.pendingCommands.append(.notice(coordinator.texts.hitNotices[.poisoned]))
        }
    }

    /// Applies `poison` straight to `target`, as a poison the Poisoned perk lets the
    /// player place in a pocket. Returns the timed effects stored, or nil.
    @discardableResult
    public func applyPlacedPoison(
        _ poison: FormID, by caster: ReferenceKey, on target: ReferenceKey
    ) -> Int? {
        guard
            let potion = coordinator.world.inventory?.baselines.items.ingestibles[poison.rawValue],
            let holder = coordinator.casterBridge
                .residentHolders(of: [SpellHitTarget(key: target)])[target]
        else { return nil }
        let plugin = coordinator.pluginName
        return coordinator.withEffects { runtime in
            MagicCoordinator.PoisonDoses.land(
                PoisonDose(potion: potion, id: poison, plugin: plugin),
                caster: caster, on: holder, using: &runtime
            )
        }
    }
}

/// One poison and the plugin its effects resolve through.
struct PoisonDose {
    let potion: Ingestible
    let id: FormID
    let plugin: String
}

extension MagicCoordinator.WeaponEnchantments {
    /// What the inventory readout shows about the profile cache.
    public var enchantmentCacheReadout: EnchantmentCacheReadout {
        coordinator.enchantingMemory.profiles.readout
    }

    /// One carried item's enchantment, or nil when it has none or the session
    /// has no ENCH index. `holder`'s best copy may carry a made one.
    public func enchantmentProfile(
        of item: FormID, on holder: InventoryHolder? = nil
    ) -> ItemEnchantmentProfile? {
        if let holder, let made = coordinator.enchantingRecords.madeProfile(of: item, on: holder) {
            return made
        }
        let store = coordinator.enchantmentStore
        let items = coordinator.world.inventory?.baselines.items
        return coordinator.enchantingMemory.profiles.profile(of: item) { item in
            guard let store, let definition = items?.definition(item) else { return nil }
            return ItemEnchantmentProfile.resolve(definition, using: store)
        }
    }

    /// What `item` has left on `holder`, or nil when it carries no enchantment.
    func enchantmentCharge(
        of item: FormID,
        on holder: ActorValueHolder
    ) -> EnchantmentCharge? {
        guard
            let runtime = coordinator.effects,
            let profile = enchantmentProfile(of: item, on: InventoryHolder(actor: holder))
        else { return nil }
        return EnchantmentLedger(store: runtime.store, inventory: coordinator.world.inventory)
            .charge(of: profile, on: holder)
    }

    /// Brings magic in line after `holder`'s worn set changed: readied spells
    /// leave the hands a worn item holds, then worn enchantments are re-read.
    @discardableResult
    public func equipmentChanged(on holder: InventoryHolder) -> WornEnchantmentReport {
        if
            let caster = coordinator.caster,
            let values = coordinator.world.actorValueHolder(for: holder.key)
        {
            caster.spellbook.releaseHands(wornBy: holder, on: values)
        }
        if let values = coordinator.world.actorValueHolder(for: holder.key) {
            coordinator.weaponArchetypes.endWeaponEnhancement(on: values)
        }
        return refreshWornEnchantments(on: holder)
    }

    /// Brings `holder`'s worn constant effects in line with what it wears. An
    /// owner with no actor values, such as a container, changes nothing.
    @discardableResult
    func refreshWornEnchantments(on holder: InventoryHolder) -> WornEnchantmentReport {
        guard
            let equipment = coordinator.world.equipment,
            let values = coordinator.world.actorValueHolder(for: holder.key)
        else { return .none }
        let worn = equipment.equipped(on: holder).compactMap {
            enchantmentProfile(of: $0, on: holder)
        }
        return coordinator.withEffects { runtime in
            WornEnchantmentApplication.reconcile(worn: worn, on: values, using: &runtime)
        } ?? .none
    }

    /// One item's enchantment and charge as words, so every readout agrees.
    /// Without a holder the full charge is reported.
    public func enchantmentLine(of item: FormID, on holder: ActorValueHolder?) -> String? {
        let owner = holder.map(InventoryHolder.init(actor:))
        guard let profile = enchantmentProfile(of: item, on: owner) else { return nil }
        let charge = holder.flatMap { enchantmentCharge(of: item, on: $0) } ?? profile.fullCharge
        let shape = profile.isWorn ? "worn" : (profile.isStaff ? "staff" : "on hit")
        return "\(profile.name) (\(shape)): \(charge.describedLine)"
    }
}
