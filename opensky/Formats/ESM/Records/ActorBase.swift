// NPC_ record decoded into engine types: the appearance-relevant subset for
// the bind-pose milestone. Stats, factions, AI, spells, perks, and inventory
// items are skipped deliberately; ACBS carries the gender flag + the
// template-inheritance flags that drive per-field resolution.
//
// Reference: UESP "Skyrim Mod:Mod File Format/NPC_"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NPC_
// Layout documented in docs/formats/actors.md.

import Foundation

nonisolated struct ActorBase {
    /// ACBS uint32 flags — only the appearance-relevant bits are named.
    struct Flags: OptionSet, Equatable {
        let rawValue: UInt32

        static let female = Flags(rawValue: 0x0000_0001)
        static let unique = Flags(rawValue: 0x0000_0020)
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
    /// WNAM — worn armor (naked skin override); race skin when absent.
    let wornArmor: FormID?
    /// PNAM — head parts, one FormID per repeated subrecord.
    let headParts: [FormID]
    /// DOFT — default outfit.
    let defaultOutfit: FormID?

    var isFemale: Bool {
        flags.contains(.female)
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
        var template: FormID?
        var race: FormID?
        var wornArmor: FormID?
        var headParts: [FormID] = []
        var defaultOutfit: FormID?
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "FULL":
                name = try LString(field: field, localized: localized)
            case "ACBS":
                (flags, templateFlags) = try Self.decodeACBS(field, npc: formID)
                sawACBS = true
            case "TPLT":
                template = try FormID(reader.readUInt32())
            case "RNAM":
                race = try FormID(reader.readUInt32())
            case "WNAM":
                wornArmor = try FormID(reader.readUInt32())
            case "PNAM":
                try headParts.append(FormID(reader.readUInt32()))
            case "DOFT":
                defaultOutfit = try FormID(reader.readUInt32())
            default:
                break
            }
        }
        guard sawACBS else {
            throw ESMError.malformed("NPC_ \(formID) has no ACBS field")
        }
        self.editorID = editorID
        self.name = name
        self.flags = flags
        self.templateFlags = templateFlags
        self.template = template
        self.race = race
        self.wornArmor = wornArmor
        self.headParts = headParts
        self.defaultOutfit = defaultOutfit
    }

    /// ACBS, 24 bytes: uint32 flags, 7 stat/level words, uint16 template
    /// flags at offset 0x12, 2 tail words (layout: docs/formats/actors.md).
    private static func decodeACBS(
        _ field: ESMField,
        npc: FormID
    ) throws -> (Flags, TemplateFlags) {
        guard field.data.count >= 20 else {
            throw ESMError.malformed(
                "NPC_ \(npc) ACBS has \(field.data.count) bytes, expected 24"
            )
        }
        var reader = BinaryReader(field.data)
        let flags = try Flags(rawValue: reader.readUInt32())
        reader.skip(14)
        let templateFlags = try TemplateFlags(rawValue: reader.readUInt16())
        return (flags, templateFlags)
    }
}
