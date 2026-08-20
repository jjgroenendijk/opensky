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
// ## Which values are stored
//
// Every one of the 164 (issue #468, roadmap item 19.5). Health, magicka and
// stamina keep the typed `ActorValueKind` fast path 15.3 built for them, which
// is what `kind(at:)` still answers; every other index is stored by
// `ActorValueState`'s general table and read through `defaultValue(at:)` when
// nothing has touched it. `kind(at:)` returning nil therefore no longer means
// "unreadable" — it means "not one of the three primaries", and the question a
// caller actually asks first is `isVanilla(index:)`.
//
// An index *outside* the table stays the documented miss it always was: a
// reason-tagged false and a `ConditionTally` bucket on the condition side, a
// tallied native failure and the call's declared default on the Papyrus side.
// That bucket now counts only genuinely unknown indices and names.
//
// ## Name matching
//
// Names are compared with every non-alphanumeric character removed and the rest
// lowercased, so xEdit's `One-Handed` and Papyrus's `OneHanded` are one name and
// a script's `"health"` matches the table's `Health`. Papyrus does use a handful
// of *different* words for the same value — `Marksman` for index 8, which xEdit
// spells `Archery` — and `index(named:)` deliberately still does not alias
// those, so the measured condition and native miss buckets do not move.
//
// The AVIF records use three of the same legacy words in their editor ids, and
// those *are* mapped, in `recordNameAliases` behind the separate
// `index(recordName:)` entry point (issue #494, roadmap item 20.1).
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

    /// Actor-value index of the first and last of the eighteen skills,
    /// `One-Handed` and `Enchanting`, which are contiguous in the table above.
    /// CLAS DATA weights them in this order, one byte each (UESP CLAS).
    static let firstSkillIndex: Int32 = 6
    static let lastSkillIndex: Int32 = 23

    /// The floor every skill starts from before a race bonus or a class spread:
    /// "Skill = 15 + [Racial bonus] + 8\*(Level-1)/(Sum of class' skill
    /// weights)\*[Skill weight]"
    /// (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CLAS>).
    static let skillFloor: Float = 15

    /// Every skill index in table order, which is what a caller iterating the
    /// eighteen skills walks rather than rebuilding the range.
    static let skillIndices: [Int32] = Array(firstSkillIndex ... lastSkillIndex)

    /// Actor-value index of `One-Handed Skill Advance`, the first of the
    /// eighteen "Skill Advance" slots, which run in the same order as the
    /// skills themselves (issue #498, roadmap item 20.5).
    ///
    /// These are where accumulated skill experience lives: the table names one
    /// per skill, they hold no other quantity, and storing progress there is
    /// what lets `GetActorValue OneHandedSkillAdvance` answer the same number
    /// the progression runtime reads. `ActorValueIdentityTests` pins the name
    /// at this index and the contiguity of the run, so a table edit cannot move
    /// the mapping silently. See docs/engine/skill-advancement.md.
    static let firstSkillAdvanceIndex: Int32 = 114

    /// Actor-value index of `Carry Weight`, which a stamina level-up pick
    /// raises alongside the stamina itself (issue #499, roadmap item 20.6):
    /// "Adding to your base stamina when you level up increases your carry
    /// weight by 5" (<https://en.uesp.net/wiki/Skyrim:Stamina>).
    /// `ActorValueIdentityTests` pins the name at this index.
    static let carryWeightIndex: Int32 = 32

    /// The `Skill Advance` slot that accumulates experience for the skill at
    /// `index`, or nil when `index` is not one of the eighteen skills.
    static func skillAdvanceIndex(forSkill index: Int32) -> Int32? {
        guard isSkill(index: index) else { return nil }
        return firstSkillAdvanceIndex + (index - firstSkillIndex)
    }

    /// The skill whose experience the `Skill Advance` slot at `index` holds, or
    /// nil for every other index — the inverse of `skillAdvanceIndex(forSkill:)`.
    static func skillIndex(forAdvance index: Int32) -> Int32? {
        let skill = firstSkillIndex + (index - firstSkillAdvanceIndex)
        guard isSkill(index: skill) else { return nil }
        return skill
    }

    /// Whether `index` names an entry in the vanilla table — the question a
    /// caller asks before storing or reading a value by index.
    ///
    /// `noneIndex` and every other number outside `0 ..< vanillaNames.count`
    /// answer false: "none" is the absence of a value, not a value.
    static func isVanilla(index: Int32) -> Bool {
        index >= 0 && Int(index) < vanillaNames.count
    }

    /// Whether `index` names one of the eighteen skills.
    static func isSkill(index: Int32) -> Bool {
        index >= firstSkillIndex && index <= lastSkillIndex
    }

    /// What an actor reads for `index` when neither a record nor the session
    /// has authored anything, or nil for an index outside the table.
    ///
    /// Zero for everything but the skills, and that is a deliberate,
    /// documented position rather than a placeholder. An actor value is an
    /// accumulator: a resistance nothing grants is 0% resistance, a bonus
    /// nothing confers is +0, and an AI attribute the AIDT does not author is
    /// the bottom of its enumeration. The skills are the one family with a
    /// sourced non-zero floor, quoted above at `skillFloor`.
    ///
    /// Two values vanilla starts away from zero are *not* defaulted here,
    /// because they are authored per record rather than globally and OpenSky
    /// reads them from that record instead: `Speed Mult` (30) comes from ACBS
    /// 0x0E and `Mass` (36) from RACE DATA 0x34, both through
    /// `ActorValueDerivation.generalBaseValues(inputs:)`. An actor with no
    /// record behind it — a summon — therefore reads 0 for both, which is a
    /// stated gap rather than an invented number; see docs/engine/actor-values.md.
    static func defaultValue(at index: Int32) -> Float? {
        guard isVanilla(index: index) else { return nil }
        return isSkill(index: index) ? skillFloor : 0
    }

    /// Vanilla name of `index`, or nil when no vanilla actor value carries it.
    /// `noneIndex` reports nil like any other number outside the table: "none"
    /// is the absence of a value, not a value.
    static func name(at index: Int32) -> String? {
        guard isVanilla(index: index) else { return nil }
        return vanillaNames[Int(index)]
    }

    /// Index of the vanilla actor value `name` spells, or nil for a name no
    /// vanilla actor value carries.
    static func index(named name: String) -> Int32? {
        namesByKey[normalized(name)]
    }

    /// Editor-id vocabulary the vanilla AVIF records use for three skills the
    /// name table above spells differently, kept apart from `vanillaNames` so
    /// the table stays a verbatim copy of `wbActorValueEnum`.
    ///
    /// These are not guesses and not recalled from memory. Each record's own
    /// FULL string resolves, through Skyrim.esm's string table, to the name on
    /// the right, and `ActorValueInformationRealDataTests` pins exactly that —
    /// so the mapping is observed evidence with a standing regression check.
    /// The words are Oblivion-era skill names Skyrim kept in its editor ids;
    /// Papyrus uses `Marksman` for `Archery` the same way.
    static let recordNameAliases: [String: String] = [
        "Marksman": "Archery",
        "Speechcraft": "Speech",
        "Mysticism": "Illusion"
    ]

    /// Index of the actor value a *record* spells `name`, which is
    /// `index(named:)` widened by `recordNameAliases`.
    ///
    /// Deliberately a separate entry point rather than a widening of
    /// `index(named:)`: condition parameters and Papyrus natives carry the
    /// table's own vocabulary, and their measured miss buckets
    /// (docs/engine/actor-values.md) should not move because AVIF needed three
    /// extra spellings.
    static func index(recordName name: String) -> Int32? {
        if let index = index(named: name) {
            return index
        }
        guard let alias = aliasesByKey[normalized(name)] else { return nil }
        return index(named: alias)
    }

    /// The *primary* value `index` names, or nil for every other index in the
    /// table and for an index outside it alike.
    ///
    /// Since 19.5 this is a fast-path question, not a can-I-read-it question:
    /// nil means "goes through the general table", and `isVanilla(index:)` is
    /// what says whether the index names an actor value at all.
    static func kind(at index: Int32) -> ActorValueKind? {
        kindsByIndex[index]
    }

    /// Vanilla index of one of the three primaries, which is the inverse of
    /// `kind(at:)` and is what lets a primary be addressed through the same
    /// index-keyed override table as every other actor value (issue #496).
    ///
    /// `storedIndices` names all three, so the fallback is unreachable; it is
    /// `noneIndex` rather than a force-unwrap because an index outside the
    /// table is already the documented miss everything here answers with.
    static func index(of kind: ActorValueKind) -> Int32 {
        storedIndices[kind] ?? noneIndex
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
