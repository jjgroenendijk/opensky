// NPC_ record decoded into engine types: appearance, ACBS and CNAM stat inputs,
// the SPLO spells, PRKR perks, and SNAM factions. Inventory is skipped. ACBS
// carries the gender flag and the template flags that drive inheritance.
// Layout: docs/formats/actors.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct ActorBase: Sendable {
    /// ACBS uint32 flags — only the bits this engine consumes are named.
    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public static let female = Flags(rawValue: 0x0000_0001)
        /// "Auto calc stats": the actor's health/magicka/stamina come from
        /// race + class + level rather than from race plus the ACBS offsets
        /// alone (UESP NPC_ ACBS; CK "Stats Tab").
        public static let autoCalcStats = Flags(rawValue: 0x0000_0010)
        public static let unique = Flags(rawValue: 0x0000_0020)
        /// "PC Level Mult": the level word holds a multiplier x1000 against
        /// the player's level instead of a fixed level. The Creation Kit
        /// forces auto-calc on whenever this is set (CK "Stats Tab").
        public static let pcLevelMult = Flags(rawValue: 0x0000_0080)
    }

    /// The ACBS words the actor-value derivation reads: one Creation Kit tab and
    /// one template group (`useStats`). The offsets are signed; vanilla records use
    /// negative ones.
    public struct Stats: Equatable, Sendable {
        /// ACBS 0x08. A fixed level when `pcLevelMult` is clear, otherwise the
        /// player-level multiplier scaled by 1000.
        public var levelWord: UInt16 = 1
        /// ACBS 0x0A / 0x0C, the clamp applied to a `pcLevelMult` level.
        public var calcMinLevel: UInt16 = 0
        public var calcMaxLevel: UInt16 = 0
        /// ACBS 0x14 / 0x04 / 0x06.
        public var healthOffset: Int16 = 0
        public var magickaOffset: Int16 = 0
        public var staminaOffset: Int16 = 0
        /// ACBS 0x0E, the base of actor value 30 `Speed Mult`, in the `useStats`
        /// group. 100, the Creation Kit default, when ACBS is too short.
        public var speedMultiplier: UInt16 = 100
        /// CNAM — the CLAS whose attribute weights spread an auto-calc actor's
        /// per-level points.
        public var characterClass: FormID?
        /// DNAM's three baked uint16 values, which the Creation Kit writes for
        /// an auto-calc actor and leaves as junk otherwise (UESP NPC_ DNAM:
        /// "if auto-calc stats is on, otherwise seems to be random"). Never an
        /// input to the derivation — kept only so a probe can compare what
        /// OpenSky derives against what the editor baked.
        public var bakedHealth: Int16?
        public var bakedMagicka: Int16?
        public var bakedStamina: Int16?

        public init(
            levelWord: UInt16 = 1,
            calcMinLevel: UInt16 = 0,
            calcMaxLevel: UInt16 = 0,
            healthOffset: Int16 = 0,
            magickaOffset: Int16 = 0,
            staminaOffset: Int16 = 0,
            speedMultiplier: UInt16 = 100,
            characterClass: FormID? = nil,
            bakedHealth: Int16? = nil,
            bakedMagicka: Int16? = nil,
            bakedStamina: Int16? = nil
        ) {
            self.levelWord = levelWord
            self.calcMinLevel = calcMinLevel
            self.calcMaxLevel = calcMaxLevel
            self.healthOffset = healthOffset
            self.magickaOffset = magickaOffset
            self.staminaOffset = staminaOffset
            self.speedMultiplier = speedMultiplier
            self.characterClass = characterClass
            self.bakedHealth = bakedHealth
            self.bakedMagicka = bakedMagicka
            self.bakedStamina = bakedStamina
        }
    }

    public let formID: FormID
    public let editorID: String?
    /// FULL — display name; localized plugins store a string-table ID.
    public let name: LString?
    public let flags: Flags
    public let templateFlags: TemplateFlags
    /// TPLT — template chain target: another NPC_ or an LVLN leveled list.
    public let template: FormID?
    /// RNAM — race, required by spec.
    public let race: FormID?
    /// VTCK — voice type. It belongs to the ACBS `useTraits` inheritance
    /// group with race, gender and appearance (UESP NPC_ template flags).
    public let voiceType: FormID?
    /// WNAM — worn armor (naked skin override); race skin when absent.
    public let wornArmor: FormID?
    /// PNAM — head parts, one FormID per repeated subrecord.
    public let headParts: [FormID]
    /// DOFT — default outfit.
    public let defaultOutfit: FormID?
    /// PKID — ordered AI package stack. The first matching entry wins.
    public let packages: [FormID]
    /// SPLO — the spells the actor knows without learning them, in record order.
    /// The `SPCT` count is not read: counting entries cannot disagree with the
    /// file. Inherits through `TemplateFlags.useSpellList`.
    public let spells: [FormID]
    /// PRKR — the perks the actor is authored with, in record order. The rank
    /// byte is dead per UESP; a runtime rank is the length of an `NNAM` chain.
    /// Inherits through `TemplateFlags.useSpellList`, like `SPLO`.
    public let perks: [FormID]
    /// SNAM — the factions the actor is authored into, in record order.
    /// Inherits through `TemplateFlags.useFactions`.
    public let factions: [FactionMembership]
    /// ACBS/CNAM/DNAM stat inputs.
    public let stats: Stats
    /// AIDT — aggression, confidence, morality and assistance. Nil when absent or
    /// too short (`ActorAIData.absent` stands in). Inherits through
    /// `TemplateFlags.useAIData`, resolved beside the SNAM run.
    public let aiData: ActorAIData?
    /// CRIF — the faction this actor reports crimes to, as
    /// `Actor.GetCrimeFaction` answers. Inherits through
    /// `TemplateFlags.useFactions` beside the SNAM run.
    public let crimeFaction: FormID?
    /// VMAD — Papyrus scripts attached to the NPC_ base.
    public let scriptData: ScriptData

    public var isFemale: Bool {
        flags.contains(.female)
    }

    /// Whether stats derive from race + class + level rather than from race
    /// plus the ACBS offsets alone. `pcLevelMult` implies it: "Note that if PC
    /// Level Mult is checked, Auto Calc Stats will always be checked."
    /// (<https://ck.uesp.net/wiki/Stats_Tab>)
    public var autoCalculatesStats: Bool {
        flags.contains(.autoCalcStats) || flags.contains(.pcLevelMult)
    }

    public init(record: ESMRecord, localized: Bool) throws {
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
                try Self.decodeDNAM(field, stats: &stats)
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
        crimeFaction = references.crimeFaction
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
        var crimeFaction: FormID?
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
        case "CRIF":
            references.crimeFaction = try FormID(reader.readUInt32())
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

    /// ACBS, 24 bytes (docs/formats/actors.md). 20 bytes is the floor; the two
    /// words past the template flags are read only when present, so a truncated
    /// subrecord loses a field, not the record.
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
    /// three attributes are read.
    ///
    /// A short DNAM leaves the baked values absent: it is a cross-check, not an input.
    private static func decodeDNAM(_ field: ESMField, stats: inout Stats) throws {
        guard field.data.count >= 0x2A else { return }
        var reader = BinaryReader(field.data)
        reader.skip(0x24)
        stats.bakedHealth = try Int16(bitPattern: reader.readUInt16())
        stats.bakedMagicka = try Int16(bitPattern: reader.readUInt16())
        stats.bakedStamina = try Int16(bitPattern: reader.readUInt16())
    }
}

nonisolated extension ActorBase {
    /// ACBS template-data flags: when a bit is set and TPLT is present, the
    /// corresponding field group comes from the template, not this record.
    public struct TemplateFlags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt16

        public init(rawValue: UInt16) {
            self.rawValue = rawValue
        }

        public static let useTraits = TemplateFlags(rawValue: 0x0001)
        public static let useStats = TemplateFlags(rawValue: 0x0002)
        public static let useFactions = TemplateFlags(rawValue: 0x0004)
        public static let useSpellList = TemplateFlags(rawValue: 0x0008)
        public static let useAIData = TemplateFlags(rawValue: 0x0010)
        public static let useAIPackages = TemplateFlags(rawValue: 0x0020)
        public static let useModelAnimation = TemplateFlags(rawValue: 0x0040)
        public static let useBaseData = TemplateFlags(rawValue: 0x0080)
        public static let useInventory = TemplateFlags(rawValue: 0x0100)
        public static let useScript = TemplateFlags(rawValue: 0x0200)
        public static let useDefPackList = TemplateFlags(rawValue: 0x0400)
        public static let useAttackData = TemplateFlags(rawValue: 0x0800)
        public static let useKeywords = TemplateFlags(rawValue: 0x1000)
    }

    /// One SNAM: the FACT the actor belongs to and its rank inside it.
    ///
    /// The rank is signed — xEdit reads `itS8` — and vanilla authors negative
    /// ranks, which the Creation Kit uses to mean "a member the faction's rank
    /// titles do not name". The three bytes that follow the rank are unused in
    /// Skyrim (xEdit `wbFaction`) and are not read.
    public struct FactionMembership: Equatable, Sendable {
        public let faction: FormID
        public let rank: Int8
    }
}
