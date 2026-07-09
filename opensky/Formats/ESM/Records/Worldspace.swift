// WRLD record decoded into engine types: editor ID, display name, parent
// worldspace link, behavior flags. A WRLD record is followed by a world
// children group holding exterior cell blocks (ESMGroup walks those).
// Fields OpenSky does not need yet (map size, LOD water, climate, ...) are
// skipped; unknown modder fields are ignored by the same loop.
//
// Reference: UESP "Skyrim Mod:Mod File Format/WRLD"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/WRLD
// Layout documented in docs/formats/records.md.

import Foundation

nonisolated struct Worldspace {
    /// DATA field (uint8).
    struct Flags: OptionSet {
        let rawValue: UInt8

        static let smallWorld = Flags(rawValue: 0x01)
        static let noFastTravel = Flags(rawValue: 0x02)
        static let noLODWater = Flags(rawValue: 0x08)
        static let noLandscape = Flags(rawValue: 0x10)
        static let noSky = Flags(rawValue: 0x20)
        static let fixedDimensions = Flags(rawValue: 0x40)
        static let noGrass = Flags(rawValue: 0x80)
    }

    let formID: FormID
    /// EDID (e.g. "Tamriel"). Present on all vanilla worldspaces.
    let editorID: String?
    /// FULL — in-game name ("Skyrim").
    let name: LString?
    /// WNAM — parent worldspace this one inherits data from.
    let parent: FormID?
    let flags: Flags

    /// - Parameter localized: TES4 localized flag of the owning plugin
    ///   (`PluginHeader.isLocalized`) — decides lstring decoding.
    init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "WRLD" else {
            throw ESMError.malformed("expected WRLD record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var name: LString?
        var parent: FormID?
        var flags: Flags = []
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "FULL":
                name = try LString(field: field, localized: localized)
            case "WNAM":
                parent = try FormID(reader.readUInt32())
            case "DATA":
                flags = try Flags(rawValue: reader.readUInt8())
            default:
                break
            }
        }
        self.editorID = editorID
        self.name = name
        self.parent = parent
        self.flags = flags
    }
}
