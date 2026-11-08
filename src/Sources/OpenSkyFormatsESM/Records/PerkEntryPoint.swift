// The perk entry-point ID: the first byte of an entry-point effect's DATA.
// A raw byte plus a name table, not an enum, because an ID the table does not
// name must still survive decoding. Order: xEdit `wbEntryPointsEnum`.
// Layout and sources: docs/formats/perks.md.

import Foundation

nonisolated public struct PerkEntryPoint: Hashable, CustomStringConvertible, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// The xEdit name of this entry point, or nil for an id outside the table.
    public var name: String? {
        let index = Int(rawValue)
        guard index < Self.names.count else { return nil }
        return Self.names[index]
    }

    /// Whether the name table covers this id. False means the record authored
    /// an entry point this build does not know, which is kept and counted
    /// rather than dropped.
    public var isKnown: Bool {
        name != nil
    }

    public var description: String {
        name.map { "\($0) (\(rawValue))" } ?? "unknown entry point (\(rawValue))"
    }

    /// The entry points named in xEdit order; the array index is the on-disk
    /// byte. Kept as one list so the id-to-name mapping cannot drift.
    public static let names = [
        "Calculate Weapon Damage",
        "Calculate My Critical Hit Chance",
        "Calculate My Critical Hit Damage",
        "Calculate Mine Explode Chance",
        "Adjust Limb Damage",
        "Adjust Book Skill Points",
        "Mod Recovered Health",
        "Get Should Attack",
        "Mod Buy Prices",
        "Add Leveled List On Death",
        "Get Max Carry Weight",
        "Mod Addiction Chance",
        "Mod Addiction Duration",
        "Mod Positive Chem Duration",
        "Activate",
        "Ignore Running During Detection",
        "Ignore Broken Lock",
        "Mod Enemy Critical Hit Chance",
        "Mod Sneak Attack Mult",
        "Mod Max Placeable Mines",
        "Mod Bow Zoom",
        "Mod Recover Arrow Chance",
        "Mod Skill Use",
        "Mod Telekinesis Distance",
        "Mod Telekinesis Damage Mult",
        "Mod Telekinesis Damage",
        "Mod Bashing Damage",
        "Mod Power Attack Stamina",
        "Mod Power Attack Damage",
        "Mod Spell Magnitude",
        "Mod Spell Duration",
        "Mod Secondary Value Weight",
        "Mod Armor Weight",
        "Mod Incoming Stagger",
        "Mod Target Stagger",
        "Mod Attack Damage",
        "Mod Incoming Damage",
        "Mod Target Damage Resistance",
        "Mod Spell Cost",
        "Mod Percent Blocked",
        "Mod Shield Deflect Arrow Chance",
        "Mod Incoming Spell Magnitude",
        "Mod Incoming Spell Duration",
        "Mod Player Intimidation",
        "Mod Player Reputation",
        "Mod Favor Points",
        "Mod Bribe Amount",
        "Mod Detection Light",
        "Mod Detection Movement",
        "Mod Soul Gem Recharge",
        "Set Sweep Attack",
        "Apply Combat Hit Spell",
        "Apply Bashing Spell",
        "Apply Reanimate Spell",
        "Set Boolean Graph Variable",
        "Mod Spell Casting Sound Event",
        "Mod Pickpocket Chance",
        "Mod Detection Sneak Skill",
        "Mod Falling Damage",
        "Mod Lockpick Sweet Spot",
        "Mod Sell Prices",
        "Can Pickpocket Equipped Item",
        "Mod Lockpick Level Allowed",
        "Set Lockpick Starting Arc",
        "Set Progression Picking",
        "Make Lockpicks Unbreakable",
        "Mod Alchemy Effectiveness",
        "Apply Weapon Swing Spell",
        "Mod Commanded Actor Limit",
        "Apply Sneaking Spell",
        "Mod Player Magic Slowdown",
        "Mod Ward Magicka Absorption Pct",
        "Mod Initial Ingredient Effects Learned",
        "Purify Alchemy Ingredients",
        "Filter Activation",
        "Can Dual Cast Spell",
        "Mod Tempering Health",
        "Mod Enchantment Power",
        "Mod Soul Pct Captured to Weapon",
        "Mod Soul Gem Enchanting",
        "Mod # Applied Enchantments Allowed",
        "Set Activate Label",
        "Mod Shout OK",
        "Mod Poison Dose Count",
        "Should Apply Placed Item",
        "Mod Armor Rating",
        "Mod Lockpicking Crime Chance",
        "Mod Ingredients Harvested",
        "Mod Spell Range (Target Loc.)",
        "Mod Potions Created",
        "Mod Lockpicking Key Reward Chance",
        "Allow Mount Actor"
    ]
}
