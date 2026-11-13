// The inventory's Charge button texts. See docs/engine/inventory-menu.md#recharging.

public import OpenSkyGameData

nonisolated public enum RechargeText: String, GameSettingTextKey {
    case chooseSoulGem = "sChooseSoulGem"
    case noChargeItems = "sNoChargeItems"

    public var fallback: String {
        switch self {
        case .chooseSoulGem: "Choose Soul Gem to Use"
        case .noChargeItems: "No items to charge enchantment"
        }
    }
}
