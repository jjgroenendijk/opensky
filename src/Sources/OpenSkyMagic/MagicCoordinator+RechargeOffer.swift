// The inventory's Charge button: one carried weapon, the player's choice of filled
// gem. See docs/engine/inventory-menu.md#recharging.

public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
public import OpenSkyMagicInterface

extension MagicCoordinator.WeaponRecharge {
    /// `item` when the player carries it with a metered weapon enchantment.
    func weapon(_ item: FormID) -> RechargeableWeapon? {
        guard
            let runtime = coordinator.effects,
            let profile = coordinator.weaponEnchantments
                .enchantmentProfile(of: item, on: InventoryHolder(actor: .player)),
            !profile.isWorn
        else { return nil }
        let charge = EnchantmentLedger(store: runtime.store, inventory: coordinator.world.inventory)
            .charge(of: profile, on: .player)
        return charge.isMetered ? RechargeableWeapon(profile: profile, charge: charge) : nil
    }

    func filledGems() -> [SoulGemCandidate] {
        guard let inventory = coordinator.world.inventory else { return [] }
        return coordinator.soulTrapping.carriedGems(inventory).filter { $0.soul != .empty }
    }
}

extension MagicCoordinator.WeaponEnchantments {
    /// What is left of `item`'s charge, in percent; nil for an item without a metered one.
    public func chargePercent(of item: FormID) -> Float? {
        coordinator.weaponRecharge.chargePercent(of: item)
    }

    /// The filled gems that could recharge `item`; nil when it holds no charge to fill.
    public func rechargeOffer(for item: FormID) -> RechargeOffer? {
        coordinator.weaponRecharge.rechargeOffer(for: item)
    }

    /// Spends the offer's gem at `gemIndex` on `item`. False when nothing changed.
    @discardableResult
    public func recharge(_ item: FormID, gemIndex: Int) -> Bool {
        coordinator.weaponRecharge.recharge(item, gemIndex: gemIndex)
    }
}

extension MagicCoordinator.WeaponRecharge {
    /// What is left of `item`'s charge, in percent; nil for an item without a metered one.
    func chargePercent(of item: FormID) -> Float? {
        weapon(item).map { Self.percent($0.charge.remaining, of: $0) }
    }

    /// The filled gems that could recharge `item`; nil when it holds no charge to fill.
    func rechargeOffer(for item: FormID) -> RechargeOffer? {
        let recharge = self
        guard
            let weapon = recharge.weapon(item),
            weapon.charge.remaining < weapon.charge.capacity
        else { return nil }
        let souls = coordinator.texts.souls
        return RechargeOffer(
            currentPercent: Self.percent(weapon.charge.remaining, of: weapon),
            gems: recharge.filledGems().map { gem in
                RechargeOffer.Gem(
                    name: "\(coordinator.world.itemName(gem.item)) (\(souls.name(of: gem.soul)))",
                    addedPercent: Self.percent(
                        recharge.gemRechargeAmount(gem.soul, for: item),
                        of: weapon
                    )
                )
            }
        )
    }

    /// Spends the offer's gem at `gemIndex` on `item`. False when nothing changed.
    @discardableResult
    func recharge(_ item: FormID, gemIndex: Int) -> Bool {
        let recharge = self
        let gems = recharge.filledGems()
        guard
            let runtime = coordinator.effects, let inventory = coordinator.world.inventory,
            let weapon = recharge.weapon(item), gems.indices.contains(gemIndex)
        else { return false }
        _ = recharge.recharge(weapon, with: gems[gemIndex], runtime: runtime, inventory: inventory)
        return true
    }

    private static func percent(_ amount: Float, of weapon: RechargeableWeapon) -> Float {
        weapon.charge.capacity > 0 ? 100 * amount / weapon.charge.capacity : 0
    }
}
