// LVLN, LVLI, and LVSP leveled lists, which share one entry layout. Selection
// is deterministic for now: highest level, first among ties.
// Layout and sources: docs/formats/actors.md (LVSP: shouts-equip-slots.md).

import Foundation
import OpenSkyFormatsCore

nonisolated public struct LeveledList: Sendable {
    /// LVLF flags (UESP LVLN/LVLI flag table).
    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        /// All entries at or below player level are candidates.
        public static let calculateFromAllLevels = Flags(rawValue: 0x01)
        /// Re-roll the list for each placed count instead of once.
        public static let calculateForEach = Flags(rawValue: 0x02)
        /// Use every entry — the list is a bundle, not alternatives
        /// (e.g. ArmorStormcloakSet: boots + cuirass + gauntlets + helmet).
        public static let useAll = Flags(rawValue: 0x04)
    }

    /// One LVLO entry. UESP documents 12 bytes (uint32 level, FormID
    /// reference, uint32 count); xEdit (wbLeveledListEntry,
    /// wbDefinitionsCommon.pas dev-4.1.6) reads level as uint16 + 2 pad and
    /// accepts an 8-byte form with count defaulting to 1 — byte-identical
    /// for sane values, so decode the lenient shape.
    public struct Entry: Equatable, Sendable {
        public let level: UInt16
        public let reference: FormID
        public let count: UInt32
        /// COED — owner (NPC_ or FACT), owner condition word, and item health.
        public internal(set) var owner: FormID?
        public internal(set) var ownerCondition: UInt32?
        public internal(set) var condition: Float?
    }

    public let formID: FormID
    /// Which of LVLN, LVLI or LVSP this list came from; the entry references
    /// mean different things in each.
    public let recordType: FourCC
    public let editorID: String?
    /// LVLD — percent chance the list resolves to nothing.
    public let chanceNone: UInt8
    public let flags: Flags
    public let entries: [Entry]
    public let bounds: ObjectBounds?
    /// LLCT — the entry count as written. Advisory; `entries` is what decoded.
    public let declaredEntryCount: UInt8?
    /// LVLG — a GLOB that overrides `chanceNone`.
    public let chanceNoneGlobal: FormID?
    /// LVLN only: the model the editor shows for the list.
    public let model: ModelData?

    /// Deterministic bind-pose policy: highest level wins, first among ties.
    public var deterministicEntry: Entry? {
        entries.enumerated().min { lhs, rhs in
            lhs.element.level != rhs.element.level
                ? lhs.element.level > rhs.element.level
                : lhs.offset < rhs.offset
        }?.element
    }

    /// The record types this decoder accepts.
    public static let recordTypes: Set<FourCC> = ["LVLN", "LVLI", "LVSP"]
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        guard Self.recordTypes.contains(record.type) else {
            throw ESMError.malformed("expected LVLN/LVLI/LVSP record, got \(record.type)")
        }
        var rest = try RecordFields(record: record, types: Self.recordTypes)
        let recordID = rest.formID
        formID = recordID
        recordType = record.type

        var editorID: String?
        var chanceNone: UInt8 = 0
        var flags = Flags()
        var entries: [Entry] = []
        try rest.readEach { field in
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "LVLD":
                chanceNone = try reader.readUInt8()
            case "LVLF":
                flags = try Flags(rawValue: reader.readUInt8())
            case "LVLO":
                guard field.data.count >= 8 else {
                    throw ESMError.malformed(
                        "\(record.type) \(recordID) LVLO has \(field.data.count) bytes, "
                            + "expected 8 or 12"
                    )
                }
                let level = try reader.readUInt16()
                reader.skip(2)
                let reference = try FormID(reader.readUInt32())
                let count = field.data.count >= 12 ? try reader.readUInt32() : 1
                entries.append(Entry(level: level, reference: reference, count: count))
            case "COED":
                // Owner data for the entry just before it.
                guard !entries.isEmpty, field.data.count >= 12 else { return false }
                let owner = try FormID(reader.readUInt32())
                entries[entries.count - 1].owner = owner.nonNull
                entries[entries.count - 1].ownerCondition = try reader.readUInt32()
                entries[entries.count - 1].condition = try reader.readFloat32()
            default:
                return false
            }
            return true
        }
        bounds = rest.bounds()
        declaredEntryCount = rest.uint8("LLCT")
        chanceNoneGlobal = rest.formID("LVLG")
        model = rest.model()
        skipped = rest.finish()
        self.editorID = editorID
        self.chanceNone = chanceNone
        self.flags = flags
        self.entries = entries
    }
}
