// The item card beside the inventory list: what the selected item is and does.
// See docs/engine/inventory-menu.md.

import Foundation
import OpenSkyFormatsESM

nonisolated public struct InventoryItemCard: Equatable, Sendable {
    /// Which page of the vanilla item card shows the item.
    public enum Layout: Equatable, Sendable {
        case armour, weapon, book, food, potion, ingredient, key, soulGem, misc
    }

    public let item: FormID
    public let layout: Layout
    public let name: String
    /// The record family's word, such as "Weapon" or "Potion".
    public let kind: String
    public let value: Int32
    public let weight: Float
    /// A weapon's base damage, before skill and perks.
    public let damage: Int?
    /// An armour piece's base rating, before skill and perks.
    public let armourRating: Float?
    /// One line per effect, or "?" for an ingredient effect the player does not know.
    public let effects: [String]
    /// The enchantment and its charge, for a worn or held piece.
    public let enchantment: String?
    public let isStolen: Bool
    public let hotkey: Int?
    public let isFavourite: Bool

    public init(
        item: FormID, layout: Layout = .misc, name: String, kind: String, value: Int32,
        weight: Float,
        damage: Int? = nil, armourRating: Float? = nil, effects: [String] = [],
        enchantment: String? = nil, isStolen: Bool = false, hotkey: Int? = nil,
        isFavourite: Bool = false
    ) {
        self.item = item
        self.layout = layout
        self.name = name
        self.kind = kind
        self.value = value
        self.weight = weight
        self.damage = damage
        self.armourRating = armourRating
        self.effects = effects
        self.enchantment = enchantment
        self.isStolen = isStolen
        self.hotkey = hotkey
        self.isFavourite = isFavourite
    }

    /// The card as readout lines.
    public var lines: [String] {
        var lines = ["\(name) (\(kind))", "Value \(value), weight \(Self.number(weight))"]
        if let damage {
            lines.append("Damage \(damage)")
        }
        if let armourRating {
            lines.append("Armour \(Self.number(armourRating))")
        }
        lines += effects
        if let enchantment {
            lines.append(enchantment)
        }
        var marks: [String] = []
        if isFavourite {
            marks.append(hotkey.map { "favourite, hotkey \($0)" } ?? "favourite")
        }
        if isStolen {
            marks.append("stolen")
        }
        if !marks.isEmpty {
            lines.append(marks.joined(separator: ", "))
        }
        return lines
    }

    private static func number(_ value: Float) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }
}
