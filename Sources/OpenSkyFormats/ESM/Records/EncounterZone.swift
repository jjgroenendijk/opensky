// ECZN encounter-zone data. DATA is the 12-byte post-form-version-34
// structure; older records can end after its two FormIDs at byte 8.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/ECZN"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ECZN
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas `wbRecord(ECZN, ...)`
//     lines 6286-6306.
// Layout documented in docs/formats/records.md.

import Foundation

nonisolated public struct EncounterZone: Equatable, Sendable {
    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let neverResets = Flags(rawValue: 0x01)
        public static let matchesPlayerBelowMinimumLevel = Flags(rawValue: 0x02)
        public static let disablesCombatBoundary = Flags(rawValue: 0x04)
    }

    public let formID: FormID
    public let editorID: String?
    /// DATA +0x00: NPC_ or FACT owner.
    public let owner: FormID?
    /// DATA +0x04: associated LCTN.
    public let location: FormID?
    /// DATA +0x08: faction rank, or -1 where ownership is not faction-based.
    public let rank: Int8?
    public let minimumLevel: Int8?
    public let flags: Flags
    public let maximumLevel: Int8?
    public let skipped: ReferenceRecordTally

    public init(record: ESMRecord) throws {
        guard record.type == "ECZN" else {
            throw ESMError.malformed("expected ECZN record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var editorID: String?
        var data = EncounterZoneData()
        var tally = ReferenceRecordTally()
        for field in try record.fields() {
            do {
                var reader = BinaryReader(field.data)
                switch field.type {
                case "EDID": editorID = try reader.readZString()
                case "DATA": data = try EncounterZoneData(field.data)
                default: tally.note(.unknownField(field.type))
                }
            } catch {
                tally.note(.malformedField(field.type))
            }
        }
        self.editorID = editorID
        owner = data.owner
        location = data.location
        rank = data.rank
        minimumLevel = data.minimumLevel
        flags = data.flags
        maximumLevel = data.maximumLevel
        skipped = tally
    }
}

nonisolated private struct EncounterZoneData {
    var owner: FormID?
    var location: FormID?
    var rank: Int8?
    var minimumLevel: Int8?
    var flags = EncounterZone.Flags()
    var maximumLevel: Int8?

    init() {}

    /// Decode only members whose explicit offset is present. UESP records two
    /// shipped 8-byte payloads; shorter mod payloads likewise lose only the
    /// fields they do not reach instead of invalidating the record.
    init(_ data: Data) throws {
        var reader = BinaryReader(data)
        if data.count >= 4 {
            owner = try Self.link(&reader)
        }
        if data.count >= 8 {
            location = try Self.link(&reader)
        }
        if data.count >= 9 {
            rank = try Int8(bitPattern: reader.readUInt8())
        }
        if data.count >= 10 {
            minimumLevel = try Int8(bitPattern: reader.readUInt8())
        }
        if data.count >= 11 {
            flags = try EncounterZone.Flags(rawValue: reader.readUInt8())
        }
        if data.count >= 12 {
            maximumLevel = try Int8(bitPattern: reader.readUInt8())
        }
    }

    private static func link(_ reader: inout BinaryReader) throws -> FormID? {
        let value = try FormID(reader.readUInt32())
        return value.isNull ? nil : value
    }
}
