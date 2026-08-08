// How the rest of the engine names an actor value (issue #375, roadmap item
// 15.8).
//
// Two surfaces address actor values by vanilla identity rather than by
// `ActorValueKind`, and they spell that identity differently. A CTDA parameter
// carries the *index* — a signed 32-bit word, -1 meaning none — while a Papyrus
// native carries the *name* as a string. Both have to land on the same three
// values 15.3 actually stores, so the mapping lives in one place instead of
// being written twice with two chances to disagree.
//
// ## Where the table came from
//
// The index list is xEdit's `wbActorValueEnum`, dev-4.1.6
// `Core/wbDefinitionsTES5.pas`, which numbers 0 `Aggression` through 163
// `Reflect Damage` with -1 spelled `None`. It is reproduced verbatim, including
// the `Unknown NN` placeholders xEdit carries for the indices Skyrim leaves
// unnamed, because a table that silently renumbers around a gap would put every
// later index one off. Nothing here was recalled from memory: `Health` is 24,
// `Magicka` is 25 and `Stamina` is 26 because that file says so.
//
// ## What "the handful 15.3 implements" means
//
// Exactly health, magicka and stamina. Every other index and name is a real
// actor value that OpenSky has no store for, and `kind(at:)` answers nil for
// it. Callers turn that nil into their own subsystem's documented miss — a
// reason-tagged false and a `ConditionTally` bucket on the condition side, a
// tallied native failure and the call's declared default on the Papyrus side —
// so an unstored actor value is a measurable gap rather than a convincing zero.
//
// ## Name matching
//
// Names are compared with every non-alphanumeric character removed and the rest
// lowercased, so xEdit's `One-Handed` and Papyrus's `OneHanded` are one name and
// a script's `"health"` matches the table's `Health`. Papyrus does use a handful
// of *different* words for the same value — `Marksman` for index 8, which xEdit
// spells `Archery` — and those are deliberately not aliased: none of them names
// a value 15.3 stores, so an alias table would only change which unimplemented
// bucket the miss lands in.
//
// Documented in docs/engine/actor-values.md.

import Foundation

/// Vanilla actor-value identity: index to name, name to index, and either to
/// the three values the runtime stores.
nonisolated enum ActorValueIdentity {
    /// The index a CTDA or a script uses to mean "no actor value".
    static let noneIndex: Int32 = -1

    /// `wbActorValueEnum` in file order, so `vanillaNames[n]` is index `n`.
    static let vanillaNames: [String] = [
        "Aggression", "Confidence", "Energy", "Morality",
        "Mood", "Assistance", "One-Handed", "Two-Handed",
        "Archery", "Block", "Smithing", "Heavy Armor",
        "Light Armor", "Pickpocket", "Lockpicking", "Sneak",
        "Alchemy", "Speech", "Alteration", "Conjuration",
        "Destruction", "Illusion", "Restoration", "Enchanting",
        "Health", "Magicka", "Stamina", "Heal Rate",
        "Magicka Rate", "Stamina Rate", "Speed Mult", "Inventory Weight",
        "Carry Weight", "Critical Chance", "Melee Damage", "Unarmed Damage",
        "Mass", "Voice Points", "Voice Rate", "Damage Resist",
        "Poison Resist", "Resist Fire", "Resist Shock", "Resist Frost",
        "Resist Magic", "Resist Disease", "Unknown 46", "Unknown 47",
        "Unknown 48", "Unknown 49", "Unknown 50", "Unknown 51",
        "Unknown 52", "Paralysis", "Invisibility", "Night Eye",
        "Detect Life Range", "Water Breathing", "Water Walking", "Unknown 59",
        "Fame", "Infamy", "Jumping Bonus", "Ward Power",
        "Right Item Charge", "Armor Perks", "Shield Perks", "Ward Deflection",
        "Variable01", "Variable02", "Variable03", "Variable04",
        "Variable05", "Variable06", "Variable07", "Variable08",
        "Variable09", "Variable10", "Bow Speed Bonus", "Favor Active",
        "Favors Per Day", "Favors Per Day Timer", "Left Item Charge",
        "Absorb Chance", "Blindness", "Weapon Speed Mult",
        "Shout Recovery Mult", "Bow Stagger Bonus", "Telekinesis",
        "Favor Points Bonus", "Last Bribed Intimidated", "Last Flattered",
        "Movement Noise Mult", "Bypass Vendor Stolen Check",
        "Bypass Vendor Keyword Check", "Waiting For Player",
        "One-Handed Modifier", "Two-Handed Modifier", "Marksman Modifier",
        "Block Modifier", "Smithing Modifier", "Heavy Armor Modifier",
        "Light Armor Modifier", "Pickpocket Modifier", "Lockpicking Modifier",
        "Sneaking Modifier", "Alchemy Modifier", "Speechcraft Modifier",
        "Alteration Modifier", "Conjuration Modifier", "Destruction Modifier",
        "Illusion Modifier", "Restoration Modifier", "Enchanting Modifier",
        "One-Handed Skill Advance", "Two-Handed Skill Advance",
        "Marksman Skill Advance", "Block Skill Advance",
        "Smithing Skill Advance", "Heavy Armor Skill Advance",
        "Light Armor Skill Advance", "Pickpocket Skill Advance",
        "Lockpicking Skill Advance", "Sneaking Skill Advance",
        "Alchemy Skill Advance", "Speechcraft Skill Advance",
        "Alteration Skill Advance", "Conjuration Skill Advance",
        "Destruction Skill Advance", "Illusion Skill Advance",
        "Restoration Skill Advance", "Enchanting Skill Advance",
        "Left Weapon Speed Multiply", "Dragon Souls",
        "Combat Health Regen Multiply", "One-Handed Power Modifier",
        "Two-Handed Power Modifier", "Marksman Power Modifier",
        "Block Power Modifier", "Smithing Power Modifier",
        "Heavy Armor Power Modifier", "Light Armor Power Modifier",
        "Pickpocket Power Modifier", "Lockpicking Power Modifier",
        "Sneaking Power Modifier", "Alchemy Power Modifier",
        "Speechcraft Power Modifier", "Alteration Power Modifier",
        "Conjuration Power Modifier", "Destruction Power Modifier",
        "Illusion Power Modifier", "Restoration Power Modifier",
        "Enchanting Power Modifier", "Dragon Rend", "Attack Damage Mult",
        "Heal Rate Mult", "Magicka Rate Mult", "Stamina Rate Mult",
        "Werewolf Perks", "Vampire Perks", "Grab Actor Offset", "Grabbed",
        "Unknown 162", "Reflect Damage"
    ]

    /// Index of each value the runtime stores, per the table above.
    static let storedIndices: [ActorValueKind: Int32] = [
        .health: 24, .magicka: 25, .stamina: 26
    ]

    /// Vanilla name of `index`, or nil when no vanilla actor value carries it.
    /// `noneIndex` reports nil like any other number outside the table: "none"
    /// is the absence of a value, not a value.
    static func name(at index: Int32) -> String? {
        guard index >= 0, Int(index) < vanillaNames.count else { return nil }
        return vanillaNames[Int(index)]
    }

    /// Index of the vanilla actor value `name` spells, or nil for a name no
    /// vanilla actor value carries.
    static func index(named name: String) -> Int32? {
        namesByKey[normalized(name)]
    }

    /// The stored value `index` names, or nil for a real actor value 15.3 has
    /// no store for and for an index outside the table alike. The two are the
    /// same answer to the caller — "not something this engine can read" — and
    /// `name(at:)` is what tells them apart in a report.
    static func kind(at index: Int32) -> ActorValueKind? {
        kindsByIndex[index]
    }

    /// The stored value `name` spells, by the same rule as `kind(at:)`.
    static func kind(named name: String) -> ActorValueKind? {
        guard let index = index(named: name) else { return nil }
        return kind(at: index)
    }

    /// A report-safe spelling of whatever a caller was given: the vanilla name
    /// when the index names one, and the bare number otherwise, so a tally line
    /// always names something.
    static func description(of index: Int32) -> String {
        name(at: index) ?? "actor value \(index)"
    }

    // MARK: - Private

    private static let kindsByIndex: [Int32: ActorValueKind] = storedIndices
        .reduce(into: [:]) { table, entry in table[entry.value] = entry.key }

    private static let namesByKey: [String: Int32] = vanillaNames
        .enumerated()
        .reduce(into: [:]) { table, entry in
            table[normalized(entry.element)] = Int32(entry.offset)
        }

    /// Lowercased with every non-alphanumeric character dropped, which is what
    /// makes `One-Handed`, `OneHanded` and `one handed` one key.
    private static func normalized(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
