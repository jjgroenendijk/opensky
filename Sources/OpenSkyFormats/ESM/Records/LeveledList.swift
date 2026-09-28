// LVLN / LVLI / LVSP records decoded into engine types: leveled NPC, leveled
// item and leveled spell lists. All three share the LVLD/LVLF/LVLO layout
// (UESP documents the entry struct once for LVLN and LVLI; xEdit's LVSP
// definition reuses the same `wbLeveledListEntry`, differing only in the
// record types an entry may name — LVSP or SPEL instead of NPC_ or an item).
// A TPLT chain may route through an LVLN; an OTFT outfit entry may route
// through an LVLI. The bind-pose milestone picks one entry deterministically
// (highest level, first among ties) instead of rolling against player level +
// chance-none.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/LVLN" + ".../LVLI" (entry struct shared)
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/LVLN
//   UESP "Skyrim Mod:Mod File Format/LVSP"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/LVSP
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas
//     `wbRecord(LVSP, 'Leveled Spell', ...)` line 8058.
// Layout documented in docs/formats/actors.md, and for LVSP in
// docs/formats/shouts-equip-slots.md.

import Foundation

nonisolated package struct LeveledList {
    /// LVLF flags (UESP LVLN/LVLI flag table).
    package struct Flags: OptionSet, Equatable {
        package let rawValue: UInt8

        package init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        /// All entries at or below player level are candidates.
        package static let calculateFromAllLevels = Flags(rawValue: 0x01)
        /// Re-roll the list for each placed count instead of once.
        package static let calculateForEach = Flags(rawValue: 0x02)
        /// Use every entry — the list is a bundle, not alternatives
        /// (e.g. ArmorStormcloakSet: boots + cuirass + gauntlets + helmet).
        package static let useAll = Flags(rawValue: 0x04)
    }

    /// One LVLO entry. UESP documents 12 bytes (uint32 level, FormID
    /// reference, uint32 count); xEdit (wbLeveledListEntry,
    /// wbDefinitionsCommon.pas dev-4.1.6) reads level as uint16 + 2 pad and
    /// accepts an 8-byte form with count defaulting to 1 — byte-identical
    /// for sane values, so decode the lenient shape.
    package struct Entry: Equatable {
        package let level: UInt16
        package let reference: FormID
        package let count: UInt32
    }

    package let formID: FormID
    /// Which of LVLN, LVLI or LVSP this list came from; the entry references
    /// mean different things in each.
    package let recordType: FourCC
    package let editorID: String?
    /// LVLD — percent chance the list resolves to nothing.
    package let chanceNone: UInt8
    package let flags: Flags
    package let entries: [Entry]

    /// Deterministic bind-pose policy: highest level wins, first among ties.
    package var deterministicEntry: Entry? {
        entries.enumerated().min { lhs, rhs in
            lhs.element.level != rhs.element.level
                ? lhs.element.level > rhs.element.level
                : lhs.offset < rhs.offset
        }?.element
    }

    /// The record types this decoder accepts.
    package static let recordTypes: Set<FourCC> = ["LVLN", "LVLI", "LVSP"]

    package init(record: ESMRecord) throws {
        guard Self.recordTypes.contains(record.type) else {
            throw ESMError.malformed("expected LVLN/LVLI/LVSP record, got \(record.type)")
        }
        formID = FormID(record.formID)
        recordType = record.type

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
                        "\(record.type) \(formID) LVLO has \(field.data.count) bytes, "
                            + "expected 8 or 12"
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
