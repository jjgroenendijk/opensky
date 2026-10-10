// Maps a vanilla actor-value index (used by CTDA) or name (used by Papyrus) to
// one actor value. The table is xEdit's `wbActorValueEnum` unchanged, with its
// `Unknown NN` gaps, so no later index moves by one.
// Documented in docs/engine/actor-value-names.md.

import Foundation

/// Vanilla actor-value identity: index to name, name to index, and either to
/// the three values the runtime stores (`ActorValueIdentity+Kind.swift`).
nonisolated public enum ActorValueIdentity: Sendable {
    /// The index a CTDA or a script uses to mean "no actor value".
    public static let noneIndex: Int32 = -1

    /// `wbActorValueEnum` in file order, so `vanillaNames[n]` is index `n`.
    public static let vanillaNames: [String] = [
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

    /// Actor-value index of the first and last of the eighteen skills,
    /// `One-Handed` and `Enchanting`, which are contiguous in the table above.
    /// CLAS DATA weights them in this order, one byte each (UESP CLAS).
    public static let firstSkillIndex: Int32 = 6
    public static let lastSkillIndex: Int32 = 23

    /// The floor every skill starts from before a race bonus or a class spread:
    /// "Skill = 15 + [Racial bonus] + 8\*(Level-1)/(Sum of class' skill
    /// weights)\*[Skill weight]"
    /// (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CLAS>).
    public static let skillFloor: Float = 15

    /// Every skill index in table order, which is what a caller iterating the
    /// eighteen skills walks rather than rebuilding the range.
    public static let skillIndices: [Int32] = Array(firstSkillIndex ... lastSkillIndex)

    /// Actor-value index of `One-Handed Skill Advance`, the first of the
    /// eighteen "Skill Advance" slots that hold skill experience, in skill
    /// order. See docs/engine/actor-value-store.md.
    public static let firstSkillAdvanceIndex: Int32 = 114

    /// Actor-value index of `Carry Weight`, which a stamina level-up pick also
    /// raises: "Adding to your base stamina when you level up increases your
    /// carry weight by 5" (<https://en.uesp.net/wiki/Skyrim:Stamina>).
    public static let carryWeightIndex: Int32 = 32

    /// The `Skill Advance` slot that accumulates experience for the skill at
    /// `index`, or nil when `index` is not one of the eighteen skills.
    public static func skillAdvanceIndex(forSkill index: Int32) -> Int32? {
        guard isSkill(index: index) else { return nil }
        return firstSkillAdvanceIndex + (index - firstSkillIndex)
    }

    /// The skill whose experience the `Skill Advance` slot at `index` holds, or
    /// nil for every other index — the inverse of `skillAdvanceIndex(forSkill:)`.
    public static func skillIndex(forAdvance index: Int32) -> Int32? {
        let skill = firstSkillIndex + (index - firstSkillAdvanceIndex)
        guard isSkill(index: skill) else { return nil }
        return skill
    }

    /// Whether `index` names an entry in the vanilla table — the question a
    /// caller asks before storing or reading a value by index.
    ///
    /// `noneIndex` and every other number outside `0 ..< vanillaNames.count`
    /// answer false: "none" is the absence of a value, not a value.
    public static func isVanilla(index: Int32) -> Bool {
        index >= 0 && Int(index) < vanillaNames.count
    }

    /// Whether `index` names one of the eighteen skills.
    public static func isSkill(index: Int32) -> Bool {
        index >= firstSkillIndex && index <= lastSkillIndex
    }

    /// What an actor reads for `index` when nothing authored a value, or nil
    /// outside the table. Zero except for skills: an actor value accumulates
    /// from zero. See docs/engine/actor-value-names.md.
    public static func defaultValue(at index: Int32) -> Float? {
        guard isVanilla(index: index) else { return nil }
        return isSkill(index: index) ? skillFloor : 0
    }

    /// Vanilla name of `index`, or nil when no vanilla actor value carries it.
    /// `noneIndex` reports nil like any other number outside the table: "none"
    /// is the absence of a value, not a value.
    public static func name(at index: Int32) -> String? {
        guard isVanilla(index: index) else { return nil }
        return vanillaNames[Int(index)]
    }

    /// Index of the vanilla actor value `name` spells, or nil for a name no
    /// vanilla actor value carries.
    public static func index(named name: String) -> Int32? {
        namesByKey[normalized(name)]
    }

    /// Older skill names that three vanilla AVIF editor IDs use, kept apart so
    /// `vanillaNames` stays a verbatim copy of `wbActorValueEnum`. Observed in
    /// Skyrim.esm; see docs/engine/actor-value-names.md.
    public static let recordNameAliases: [String: String] = [
        "Marksman": "Archery",
        "Speechcraft": "Speech",
        "Mysticism": "Illusion"
    ]

    /// Index of the actor value a record spells `name`: `index(named:)` plus
    /// `recordNameAliases`. Separate so condition and Papyrus lookups keep the
    /// table's own vocabulary.
    public static func index(recordName name: String) -> Int32? {
        if let index = index(named: name) {
            return index
        }
        guard let alias = aliasesByKey[normalized(name)] else { return nil }
        return index(named: alias)
    }

    /// A report-safe spelling of whatever a caller was given: the vanilla name
    /// when the index names one, and the bare number otherwise, so a tally line
    /// always names something.
    public static func description(of index: Int32) -> String {
        name(at: index) ?? "actor value \(index)"
    }

    // MARK: - Private

    private static let aliasesByKey: [String: String] = recordNameAliases
        .reduce(into: [:]) { table, entry in table[normalized(entry.key)] = entry.value }

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
