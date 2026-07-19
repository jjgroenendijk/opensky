// LVLN record decoded into engine types: leveled NPC list. A TPLT chain may
// route through one of these; the bind-pose milestone picks one entry
// deterministically (highest level, first among ties) instead of rolling
// against player level + chance-none.
//
// Reference: UESP "Skyrim Mod:Mod File Format/LVLN" (entry struct shared
// with LVLI): https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/LVLN
// Layout documented in docs/formats/actors.md.

import Foundation

nonisolated struct LeveledActor {
    /// LVLF flags.
    struct Flags: OptionSet, Equatable {
        let rawValue: UInt8

        /// All entries at or below player level are candidates.
        static let calculateFromAllLevels = Flags(rawValue: 0x01)
        /// Spawn every candidate instead of one.
        static let calculateForEach = Flags(rawValue: 0x02)
    }

    /// One LVLO entry. UESP documents 12 bytes (uint32 level, FormID
    /// reference, uint32 count); xEdit (wbLeveledListEntry,
    /// wbDefinitionsCommon.pas dev-4.1.6) reads level as uint16 + 2 pad and
    /// accepts an 8-byte form with count defaulting to 1 — byte-identical
    /// for sane values, so decode the lenient shape.
    struct Entry: Equatable {
        let level: UInt16
        let reference: FormID
        let count: UInt32
    }

    let formID: FormID
    let editorID: String?
    /// LVLD — percent chance the list resolves to nothing.
    let chanceNone: UInt8
    let flags: Flags
    let entries: [Entry]

    /// Deterministic bind-pose policy: highest level wins, first among ties.
    var deterministicEntry: Entry? {
        entries.enumerated().min { lhs, rhs in
            lhs.element.level != rhs.element.level
                ? lhs.element.level > rhs.element.level
                : lhs.offset < rhs.offset
        }?.element
    }

    init(record: ESMRecord) throws {
        guard record.type == "LVLN" else {
            throw ESMError.malformed("expected LVLN record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var chanceNone: UInt8 = 0
        var flags = Flags()
        var entries: [Entry] = []
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "LVLD":
                chanceNone = try reader.readUInt8()
            case "LVLF":
                flags = try Flags(rawValue: reader.readUInt8())
            case "LVLO":
                // COED owner data may follow an entry as its own subrecord;
                // unknown fields (incl. COED) fall through to default.
                guard field.data.count >= 8 else {
                    throw ESMError.malformed(
                        "LVLN \(formID) LVLO has \(field.data.count) bytes, expected 8 or 12"
                    )
                }
                let level = try reader.readUInt16()
                reader.skip(2)
                let reference = try FormID(reader.readUInt32())
                let count = field.data.count >= 12 ? try reader.readUInt32() : 1
                entries.append(Entry(level: level, reference: reference, count: count))
            default:
                break
            }
        }
        self.editorID = editorID
        self.chanceNone = chanceNone
        self.flags = flags
        self.entries = entries
    }
}
