// DIAL, a dialogue topic followed by a type-7 child group of INFO records.
// DATA's legacy numeric subtype is retained, but SNAM is authoritative: the
// shipped tools write SNAM after DATA because numeric subtype positions moved
// between game versions.
//
// References:
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/DIAL
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas, `wbRecord(DIAL, ...)`.

import Foundation

nonisolated struct DialogueTopic {
    enum Category: Equatable {
        case player
        case favor
        case scene
        case combat
        case favors
        case detection
        case service
        case miscellaneous
        case unknown(UInt8)

        init(rawValue: UInt8) {
            switch rawValue {
            case 0: self = .player
            case 1: self = .favor
            case 2: self = .scene
            case 3: self = .combat
            case 4: self = .favors
            case 5: self = .detection
            case 6: self = .service
            case 7: self = .miscellaneous
            default: self = .unknown(rawValue)
            }
        }
    }

    let formID: FormID
    let editorID: String?
    /// FULL, the player's topic text.
    let name: LString?
    let priority: Float
    let owningBranch: FormID?
    let owningQuest: FormID?
    let doAllBeforeRepeating: Bool
    let category: Category
    /// DATA's uint16 subtype. Kept for old records; `subtype` is reliable.
    let legacySubtype: UInt16
    /// SNAM, the authoritative four-character subtype such as HELO or CUST.
    let subtype: FourCC?
    /// TIFC, an allocation hint only. The store trusts the group contents.
    let declaredInfoCount: Int?
    let skipped: DialogueTally

    init(record: ESMRecord, localized: Bool = false) throws {
        guard record.type == "DIAL" else {
            throw ESMError.malformed("expected DIAL record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var contents = Contents(localized: localized)
        for field in try record.fields() {
            contents.decode(field: field)
        }
        editorID = contents.editorID
        name = contents.name
        priority = contents.priority
        owningBranch = contents.owningBranch
        owningQuest = contents.owningQuest
        doAllBeforeRepeating = contents.doAllBeforeRepeating
        category = contents.category
        legacySubtype = contents.legacySubtype
        subtype = contents.subtype
        declaredInfoCount = contents.declaredInfoCount
        skipped = contents.tally
    }
}

nonisolated extension DialogueTopic {
    struct Contents {
        let localized: Bool
        var editorID: String?
        var name: LString?
        var priority: Float = 0
        var owningBranch: FormID?
        var owningQuest: FormID?
        var doAllBeforeRepeating = false
        var category = Category.player
        var legacySubtype: UInt16 = 0
        var subtype: FourCC?
        var declaredInfoCount: Int?
        var tally = DialogueTally()

        mutating func decode(field: ESMField) {
            do {
                if try decodeKnown(field: field) {
                    return
                }
                tally.note(.unknownField(field.type))
            } catch {
                tally.note(.malformedField(field.type))
            }
        }

        private mutating func decodeKnown(field: ESMField) throws -> Bool {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID": editorID = try reader.readZString()
            case "FULL": name = try LString(field: field, localized: localized)
            case "PNAM": priority = try reader.readFloat32()
            case "BNAM": owningBranch = try Self.readReference(&reader)
            case "QNAM": owningQuest = try Self.readReference(&reader)
            case "DATA": try decodeData(field)
            case "SNAM": subtype = try reader.readFourCC()
            case "TIFC": declaredInfoCount = try Int(reader.readUInt32())
            default: return false
            }
            return true
        }

        /// DATA is four bytes in xEdit: bool, category, uint16 legacy subtype.
        private mutating func decodeData(_ field: ESMField) throws {
            guard field.data.count >= 4 else {
                throw BinaryReaderError.outOfBounds(
                    offset: 0,
                    count: 4,
                    available: field.data.count
                )
            }
            var reader = BinaryReader(field.data)
            doAllBeforeRepeating = try reader.readUInt8() != 0
            category = try Category(rawValue: reader.readUInt8())
            legacySubtype = try reader.readUInt16()
        }

        private static func readReference(_ reader: inout BinaryReader) throws -> FormID? {
            let value = try FormID(reader.readUInt32())
            return value.isNull ? nil : value
        }
    }
}
