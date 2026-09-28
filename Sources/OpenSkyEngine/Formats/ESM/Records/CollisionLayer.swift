// COLL collision-layer metadata and links.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/COLL"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/COLL
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas `wbRecord(COLL, ...)`
//     lines 7614-7637.
// Layout documented in docs/formats/records.md.

import Foundation

nonisolated struct CollisionLayer: Equatable {
    struct Flags: OptionSet, Equatable {
        let rawValue: UInt32

        static let triggerVolume = Flags(rawValue: 0x01)
        static let sensor = Flags(rawValue: 0x02)
        static let navmeshObstacle = Flags(rawValue: 0x04)
    }

    let formID: FormID
    let editorID: String?
    let recordDescription: LString?
    let index: UInt32?
    let debugColor: ReferenceRecordColor?
    let flags: Flags
    let name: String?
    let interactablesCount: UInt32?
    /// CNAM links. Resolution is plugin-relative and therefore belongs to
    /// `CollisionLayerStore`, which exposes `ResolvedFormID` values.
    let collidesWith: [FormID]
    let skipped: ReferenceRecordTally

    init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "COLL" else {
            throw ESMError.malformed("expected COLL record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var fields = CollisionLayerFields()
        for field in try record.fields() {
            fields.decode(field: field, localized: localized)
        }
        editorID = fields.editorID
        recordDescription = fields.recordDescription
        index = fields.index
        debugColor = fields.debugColor
        flags = fields.flags
        name = fields.name
        interactablesCount = fields.interactablesCount
        collidesWith = fields.collidesWith
        skipped = fields.skipped
    }
}

nonisolated private struct CollisionLayerFields {
    var editorID: String?
    var recordDescription: LString?
    var index: UInt32?
    var debugColor: ReferenceRecordColor?
    var flags = CollisionLayer.Flags()
    var name: String?
    var interactablesCount: UInt32?
    var collidesWith: [FormID] = []
    var skipped = ReferenceRecordTally()

    mutating func decode(field: ESMField, localized: Bool) {
        do {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID": editorID = try reader.readZString()
            case "DESC": recordDescription = try LString(field: field, localized: localized)
            case "BNAM": index = try reader.readUInt32()
            case "FNAM": debugColor = try ReferenceRecordColor(reader: &reader)
            case "GNAM": flags = try CollisionLayer.Flags(rawValue: reader.readUInt32())
            case "MNAM": name = try reader.readZString()
            case "INTV": interactablesCount = try reader.readUInt32()
            case "CNAM": collidesWith = try decodeLinks(field.data)
            default: skipped.note(.unknownField(field.type))
            }
        } catch {
            skipped.note(.malformedField(field.type))
        }
    }

    private mutating func decodeLinks(_ data: Data) throws -> [FormID] {
        guard data.count % 4 == 0 else {
            skipped.note(.malformedField("CNAM"))
            return []
        }
        var reader = BinaryReader(data)
        var links: [FormID] = []
        links.reserveCapacity(data.count / 4)
        while reader.bytesRemaining >= 4 {
            let link = try FormID(reader.readUInt32())
            if !link.isNull {
                links.append(link)
            }
        }
        return links
    }
}
