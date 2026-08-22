// NPC_ record decoded into engine types: the appearance-relevant subset for
// the bind-pose milestone, plus the ACBS/CNAM stat inputs the actor-value
// derivation needs (issue #194), the SPLO spell run (issue #470) and the PRKR
// perk run (issue #497) and the SNAM faction memberships (issue #501). AI and
// inventory items are still skipped deliberately; ACBS carries the gender flag + the
// template-inheritance flags that drive per-field resolution.
//
// Reference: UESP "Skyrim Mod:Mod File Format/NPC_"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NPC_
// Layout documented in docs/formats/actors.md.

import Foundation

nonisolated struct ActorBase {
    /// ACBS uint32 flags — only the bits this engine consumes are named.
    struct Flags: OptionSet, Equatable {
        let rawValue: UInt32

        static let female = Flags(rawValue: 0x0000_0001)
        /// "Auto calc stats": the actor's health/magicka/stamina come from
        /// race + class + level rather than from race plus the ACBS offsets
        /// alone (UESP NPC_ ACBS; CK "Stats Tab").
        static let autoCalcStats = Flags(rawValue: 0x0000_0010)
        static let unique = Flags(rawValue: 0x0000_0020)
        /// "PC Level Mult": the level word holds a multiplier x1000 against
        /// the player's level instead of a fixed level. The Creation Kit
        /// forces auto-calc on whenever this is set (CK "Stats Tab").
        static let pcLevelMult = Flags(rawValue: 0x0000_0080)
    }

    /// The ACBS words the actor-value derivation reads, kept together because
    /// they are one authoring surface (the Creation Kit's Stats tab) and one
    /// template-flag group (`useStats`).
    ///
    /// The three offsets are signed: the Creation Kit calls them "an amount to
    /// add or subtract from the calculated value" and vanilla records use
    /// negative offsets freely.
    struct Stats: Equatable {
        /// ACBS 0x08. A fixed level when `pcLevelMult` is clear, otherwise the
        /// player-level multiplier scaled by 1000.
        var levelWord: UInt16 = 1
        /// ACBS 0x0A / 0x0C, the clamp applied to a `pcLevelMult` level.
        var calcMinLevel: UInt16 = 0
        var calcMaxLevel: UInt16 = 0
        /// ACBS 0x14 / 0x04 / 0x06.
        var healthOffset: Int16 = 0
        var magickaOffset: Int16 = 0
        var staminaOffset: Int16 = 0
        /// ACBS 0x0E "Speed Multiplier" (UESP NPC_ ACBS), which is the base of
        /// actor value 30, `Speed Mult` (issue #468). It belongs to the
        /// `useStats` template group with the three offsets — UESP names the
        /// group's contents as "level, autocalc, skills, health/magicka/stamina,
        /// speed, bleedout, class" — so it resolves through the same chain.
        ///
        /// 100 when ACBS is too short to reach it, which is the Creation Kit's
        /// own default for an actor nobody has slowed down or sped up.
        var speedMultiplier: UInt16 = 100
        /// CNAM — the CLAS whose attribute weights spread an auto-calc actor's
        /// per-level points.
        var characterClass: FormID?
        /// DNAM's three baked uint16 values, which the Creation Kit writes for
        /// an auto-calc actor and leaves as junk otherwise (UESP NPC_ DNAM:
        /// "if auto-calc stats is on, otherwise seems to be random"). Never an
        /// input to the derivation — kept only so a probe can compare what
        /// OpenSky derives against what the editor baked.
        var bakedHealth: Int16?
        var bakedMagicka: Int16?
        var bakedStamina: Int16?
    }

    /// ACBS template-data flags: when a bit is set and TPLT is present, the
    /// corresponding field group comes from the template, not this record.
    struct TemplateFlags: OptionSet, Equatable {
        let rawValue: UInt16

        static let useTraits = TemplateFlags(rawValue: 0x0001)
        static let useStats = TemplateFlags(rawValue: 0x0002)
        static let useFactions = TemplateFlags(rawValue: 0x0004)
        static let useSpellList = TemplateFlags(rawValue: 0x0008)
        static let useAIData = TemplateFlags(rawValue: 0x0010)
        static let useAIPackages = TemplateFlags(rawValue: 0x0020)
        static let useModelAnimation = TemplateFlags(rawValue: 0x0040)
        static let useBaseData = TemplateFlags(rawValue: 0x0080)
        static let useInventory = TemplateFlags(rawValue: 0x0100)
        static let useScript = TemplateFlags(rawValue: 0x0200)
        static let useDefPackList = TemplateFlags(rawValue: 0x0400)
        static let useAttackData = TemplateFlags(rawValue: 0x0800)
        static let useKeywords = TemplateFlags(rawValue: 0x1000)
    }

    /// One SNAM: the FACT the actor belongs to and its rank inside it.
    ///
    /// The rank is signed — xEdit reads `itS8` — and vanilla authors negative
    /// ranks, which the Creation Kit uses to mean "a member the faction's rank
    /// titles do not name". The three bytes that follow the rank are unused in
    /// Skyrim (xEdit `wbFaction`) and are not read.
    struct FactionMembership: Equatable {
        static let byteCount = 8

        let faction: FormID
        let rank: Int8
    }

    let formID: FormID
    let editorID: String?
    /// FULL — display name; localized plugins store a string-table ID.
    let name: LString?
    let flags: Flags
    let templateFlags: TemplateFlags
    /// TPLT — template chain target: another NPC_ or an LVLN leveled list.
    let template: FormID?
    /// RNAM — race, required by spec.
    let race: FormID?
    /// VTCK — voice type. It belongs to the ACBS `useTraits` inheritance
    /// group with race, gender and appearance (UESP NPC_ template flags).
    let voiceType: FormID?
    /// WNAM — worn armor (naked skin override); race skin when absent.
    let wornArmor: FormID?
    /// PNAM — head parts, one FormID per repeated subrecord.
    let headParts: [FormID]
    /// DOFT — default outfit.
    let defaultOutfit: FormID?
    /// PKID — ordered AI package stack. The first matching entry wins.
    let packages: [FormID]
    /// SPLO — the actor's spell list: the SPEL records it knows without
    /// learning them, in record order (issue #470).
    ///
    /// The preceding `SPCT` count is deliberately not read. It states how many
    /// `SPLO` entries follow, so counting the entries answers the same question
    /// and cannot disagree with the file; a record whose `SPCT` and entry count
    /// differ is then decoded rather than rejected.
    ///
    /// This list inherits through `TemplateFlags.useSpellList`, which the
    /// template chain resolves — the same rule the stats and inventory groups
    /// follow.
    let spells: [FormID]
    /// PRKR — the perks the actor is authored with, in record order
    /// (issue #497).
    ///
    /// The preceding `PRKZ` count is deliberately not read, for the reason
    /// `SPCT` is not: counting the entries answers the same question and cannot
    /// disagree with the file. The 8-byte struct's rank byte is not read
    /// either, because UESP records it as dead — "uint8 Rank (no longer in
    /// use)" — and a rank at runtime is the length of an owned `NNAM` chain
    /// (`PerkState`).
    ///
    /// This list inherits through `TemplateFlags.useSpellList`, which UESP
    /// names "Use spelllist (both spells and perks)", so it resolves on the
    /// same flag the `SPLO` run does.
    let perks: [FormID]
    /// SNAM — the factions the actor is authored into, in record order
    /// (issue #501). Consuming them for hostility, crime and services is the
    /// rest of milestone M21.
    ///
    /// This list inherits through `TemplateFlags.useFactions`, resolved by
    /// `ActorTemplateResolver.resolveFactions(base:)` the way the spell and
    /// package runs resolve on their own flags.
    let factions: [FactionMembership]
    /// ACBS/CNAM/DNAM stat inputs (issue #194).
    let stats: Stats
    /// AIDT — aggression, confidence, morality and assistance (issue #503).
    /// Nil when the record authors no AIDT or authors one too short to read,
    /// which `ActorAIData.absent` is the documented stand-in for.
    ///
    /// This struct inherits through `TemplateFlags.useAIData`, resolved by
    /// `ActorTemplateResolver.resolveFactions(base:)` beside the SNAM run,
    /// because the hostility derivation reads the two together.
    let aiData: ActorAIData?
    /// VMAD — Papyrus scripts attached to the NPC_ base.
    let scriptData: ScriptData

    var isFemale: Bool {
        flags.contains(.female)
    }

    /// Whether stats derive from race + class + level rather than from race
    /// plus the ACBS offsets alone. `pcLevelMult` implies it: "Note that if PC
    /// Level Mult is checked, Auto Calc Stats will always be checked."
    /// (<https://ck.uesp.net/wiki/Stats_Tab>)
    var autoCalculatesStats: Bool {
        flags.contains(.autoCalcStats) || flags.contains(.pcLevelMult)
    }

    init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "NPC_" else {
            throw ESMError.malformed("expected NPC_ record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var name: LString?
        var flags = Flags()
        var templateFlags = TemplateFlags()
        var sawACBS = false
        var references = References()
        var stats = Stats()
        var aiData: ActorAIData?
        var scriptData = ScriptData(ownerType: record.type)
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "FULL":
                name = try LString(field: field, localized: localized)
            case "ACBS":
                (flags, templateFlags) = try Self.decodeACBS(field, npc: formID, stats: &stats)
                sawACBS = true
            case "CNAM":
                stats.characterClass = try FormID(reader.readUInt32())
            case "DNAM":
                Self.decodeDNAM(field, stats: &stats)
            case "AIDT":
                // A malformed AIDT leaves the actor without AI data rather than
                // failing the record, the rule every optional field group here
                // follows.
                aiData = try? ActorAIData(field: field)
            default:
                // The FormID-valued appearance fields and the VMAD fallthrough
                // live in their own pass, which is what keeps this switch inside
                // the strict cyclomatic-complexity limit.
                try Self.decodeReference(
                    field,
                    into: &references,
                    scriptData: &scriptData
                )
            }
        }
        guard sawACBS else {
            throw ESMError.malformed("NPC_ \(formID) has no ACBS field")
        }
        self.editorID = editorID
        self.name = name
        self.flags = flags
        self.templateFlags = templateFlags
        template = references.template
        race = references.race
        voiceType = references.voiceType
        wornArmor = references.wornArmor
        headParts = references.headParts
        defaultOutfit = references.defaultOutfit
        packages = references.packages
        spells = references.spells
        perks = references.perks
        factions = references.factions
        self.stats = stats
        self.aiData = aiData
        self.scriptData = scriptData
    }

    /// The FormID-valued fields, gathered so the decode pass that fills them
    /// stays inside the strict parameter-count limit.
    private struct References {
        var template: FormID?
        var race: FormID?
        var voiceType: FormID?
        var wornArmor: FormID?
        var headParts: [FormID] = []
        var defaultOutfit: FormID?
        var packages: [FormID] = []
        var spells: [FormID] = []
        var perks: [FormID] = []
        var factions: [FactionMembership] = []
    }

    /// The FormID-valued fields, plus the VMAD accumulator every unrecognized
    /// field falls through to.
    private static func decodeReference(
        _ field: ESMField,
        into references: inout References,
        scriptData: inout ScriptData
    ) throws {
        var reader = BinaryReader(field.data)
        switch field.type {
        case "TPLT":
            references.template = try FormID(reader.readUInt32())
        case "RNAM":
            references.race = try FormID(reader.readUInt32())
        case "VTCK":
            references.voiceType = try FormID(reader.readUInt32())
        case "WNAM":
            references.wornArmor = try FormID(reader.readUInt32())
        case "DOFT":
            references.defaultOutfit = try FormID(reader.readUInt32())
        default:
            // The repeated list fields and the VMAD fallthrough live in their
            // own pass, which keeps this switch inside the complexity limit.
            try Self.decodeListReference(
                field,
                reader: &reader,
                into: &references,
                scriptData: &scriptData
            )
        }
    }

    /// The repeated FormID-valued runs, plus the VMAD accumulator every
    /// unrecognized field falls through to.
    private static func decodeListReference(
        _ field: ESMField,
        reader: inout BinaryReader,
        into references: inout References,
        scriptData: inout ScriptData
    ) throws {
        switch field.type {
        case "PNAM":
            try references.headParts.append(FormID(reader.readUInt32()))
        case "PKID":
            try references.packages.append(FormID(reader.readUInt32()))
        case "SPLO":
            try references.spells.append(FormID(reader.readUInt32()))
        case "PRKR":
            // 8-byte struct: the PERK link, a dead rank byte and three unused
            // bytes carrying junk (UESP NPC_ PRKR). A short one loses its entry
            // rather than failing the record.
            guard field.data.count >= 4 else { return }
            try references.perks.append(FormID(reader.readUInt32()))
        case "SNAM":
            // 8-byte struct: the FACT link, a signed rank, then three bytes
            // unused in Skyrim (xEdit `wbFaction`). A short one loses its entry
            // rather than failing the record, as PRKR does.
            guard field.data.count >= 5 else { return }
            try references.factions.append(ActorBase.FactionMembership(
                faction: FormID(reader.readUInt32()),
                rank: Int8(bitPattern: reader.readUInt8())
            ))
        default:
            _ = try scriptData.decode(field: field)
        }
    }

    /// ACBS, 24 bytes: uint32 flags, 7 stat/level words, uint16 template
    /// flags at offset 0x12, 2 tail words (layout: docs/formats/actors.md).
    ///
    /// The 20-byte floor is what the appearance decode has always required, so
    /// a short-but-usable ACBS keeps resolving; the two words past the template
    /// flags are read only when they are actually there, leaving the health
    /// offset at its zero default otherwise. That is the defensive-parse rule:
    /// a truncated subrecord loses a field, it does not fail the record.
    private static func decodeACBS(
        _ field: ESMField,
        npc: FormID,
        stats: inout Stats
    ) throws -> (Flags, TemplateFlags) {
        guard field.data.count >= 20 else {
            throw ESMError.malformed(
                "NPC_ \(npc) ACBS has \(field.data.count) bytes, expected 24"
            )
        }
        var reader = BinaryReader(field.data)
        let flags = try Flags(rawValue: reader.readUInt32())
        stats.magickaOffset = try Int16(bitPattern: reader.readUInt16())
        stats.staminaOffset = try Int16(bitPattern: reader.readUInt16())
        stats.levelWord = try reader.readUInt16()
        stats.calcMinLevel = try reader.readUInt16()
        stats.calcMaxLevel = try reader.readUInt16()
        stats.speedMultiplier = try reader.readUInt16()
        reader.skip(2) // disposition base — AI data, not an actor value here.
        let templateFlags = try TemplateFlags(rawValue: reader.readUInt16())
        if field.data.count >= 22 {
            stats.healthOffset = try Int16(bitPattern: reader.readUInt16())
        }
        return (flags, templateFlags)
    }

    /// DNAM, 52 bytes: 18 base skills, 18 skill mods, then the three baked
    /// uint16 attribute values at 0x24 / 0x26 / 0x28 (UESP NPC_ DNAM). Only the
    /// three attributes are read; the skill bytes wait for M18.
    ///
    /// Nothing throws here. DNAM is a cross-check rather than an input, so a
    /// short one simply leaves the baked values absent.
    private static func decodeDNAM(_ field: ESMField, stats: inout Stats) {
        guard field.data.count >= 0x2A else { return }
        var reader = BinaryReader(field.data)
        reader.skip(0x24)
        stats.bakedHealth = (try? reader.readUInt16()).map { Int16(bitPattern: $0) }
        stats.bakedMagicka = (try? reader.readUInt16()).map { Int16(bitPattern: $0) }
        stats.bakedStamina = (try? reader.readUInt16()).map { Int16(bitPattern: $0) }
    }
}
