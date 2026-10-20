// What an enchanted weapon or armour is worth in game. The record's value is the
// unenchanted one; the game adds the enchantment on top. UESP "Skyrim Mod:Mod File
// Format/WEAP" and ".../ARMO". See docs/engine/barter.md.

import Foundation
import OpenSkyFormatsESM

/// `fEnchantmentPointsMult` and `fEnchantmentEffectPointsMult`, the two weapon terms.
nonisolated public struct EnchantedValueSettings: Equatable, Sendable {
    /// Gold per point of the weapon's `EAMT` charge.
    public var chargeMult: Float = 0.12
    /// Gold per point of the weapon enchantment's cost.
    public var costMult: Float = 8

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fEnchantmentPointsMult", into: &settings, \.chargeMult)
        store.read("fEnchantmentEffectPointsMult", into: &settings, \.costMult)
        return settings
    }
}

nonisolated extension ItemDefinitionStore {
    /// The value the game shows and charges for `item`, with its enchantment. Zero
    /// for a form no loaded plugin describes.
    public func gameValue(of item: FormID) -> Int32 {
        definition(item).map { enchantedValue(of: $0, settings: enchantedValueSettings) } ?? 0
    }

    /// `definition`'s value with its enchantment: a weapon adds
    /// `chargeMult * EAMT + costMult * cost`, an armour `cost + 0.5`, both rounded
    /// down. The cost is the exact auto-calculated sum, or the authored one on a
    /// manual-cost enchantment.
    public func enchantedValue(
        of definition: ItemDefinition, settings: EnchantedValueSettings = .vanilla
    ) -> Int32 {
        guard let enchantment = enchantment(of: definition) else { return definition.value }
        let cost = enchantment.cost.isManual
            ? Float(enchantment.cost.cost) : enchantment.cost.autoCalculated
        let added: Float = switch definition.family {
        case .weapon:
            settings.chargeMult * Float(definition.enchantment?.charge ?? 0)
                + settings.costMult * cost
        case .armor:
            cost + 0.5
        default:
            0
        }
        guard added.isFinite, added > 0 else { return definition.value }
        let total = Float(definition.value) + added.rounded(.down)
        return Int32(clamping: Int(min(total, Float(Int32.max))))
    }
}
