// The perk entry-point identifier: the first byte of a PERK entry-point
// effect's DATA, and the key combat and magic formulas query at runtime.
//
// Modelled as a raw byte with a name table rather than a 92-case enum. The id
// is what the runtime index keys on, an id the table does not name still has
// to survive decoding (a later game or a mod may author one), and the names
// exist only for inspection surfaces — so the byte is the value and the name
// is a lookup, not the other way round.
//
// References:
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas, `wbEntryPointsEnum` (line
//     2426), which is the authoritative ordering used here.
//   UESP "Skyrim Mod:Mod File Format/PERK", "Perk Effect Types", which lists
//     the same set by hexadecimal id together with the condition-tab count
//     each entry point expects.
// Layout documented in docs/formats/perks.md.

import Foundation

nonisolated struct PerkEntryPoint: Hashable, CustomStringConvertible, Sendable {
    let rawValue: UInt8

    /// The xEdit name of this entry point, or nil for an id outside the table.
    var name: String? {
        let index = Int(rawValue)
        guard index < Self.names.count else { return nil }
        return Self.names[index]
    }

    /// Whether the name table covers this id. False means the record authored
    /// an entry point this build does not know, which is kept and counted
    /// rather than dropped.
    var isKnown: Bool {
        name != nil
    }

    var description: String {
        name.map { "\($0) (\(rawValue))" } ?? "unknown entry point (\(rawValue))"
    }

    /// The entry points named in xEdit order; the array index is the on-disk
    /// byte. Kept as one list so the id-to-name mapping cannot drift.
    static let names = [
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
