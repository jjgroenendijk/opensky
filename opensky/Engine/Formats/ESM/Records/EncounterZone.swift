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

nonisolated struct EncounterZone: Equatable, Sendable {
    struct Flags: OptionSet, Equatable, Sendable {
        let rawValue: UInt8

        static let neverResets = Flags(rawValue: 0x01)
        static let matchesPlayerBelowMinimumLevel = Flags(rawValue: 0x02)
        static let disablesCombatBoundary = Flags(rawValue: 0x04)
    }

    let formID: FormID
    let editorID: String?
    /// DATA +0x00: NPC_ or FACT owner.
    let owner: FormID?
    /// DATA +0x04: associated LCTN.
    let location: FormID?
    /// DATA +0x08: faction rank, or -1 where ownership is not faction-based.
    let rank: Int8?
    let minimumLevel: Int8?
    let flags: Flags
    let maximumLevel: Int8?
    let skipped: ReferenceRecordTally

    init(record: ESMRecord) throws {
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
