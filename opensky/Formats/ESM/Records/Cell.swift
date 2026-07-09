// CELL record decoded into engine types: flags (interior/water), exterior
// grid coordinates, display name. Shared by interior cells (CELL top group)
// and exterior cells (inside WRLD children); references live in the cell
// children group that follows the record.
//
// Reference: UESP "Skyrim Mod:Mod File Format/CELL"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CELL
// Layout documented in docs/formats/records.md.

import Foundation

nonisolated struct Cell {
    /// DATA field (uint16; one byte in some records — see init).
    struct Flags: OptionSet {
        let rawValue: UInt16

        static let interior = Flags(rawValue: 0x0001)
        static let hasWater = Flags(rawValue: 0x0002)
        static let noTravelFromHere = Flags(rawValue: 0x0004)
        static let noLODWater = Flags(rawValue: 0x0008)
        static let publicArea = Flags(rawValue: 0x0020)
        static let handChanged = Flags(rawValue: 0x0040)
        static let showSky = Flags(rawValue: 0x0080)
        static let useSkyLighting = Flags(rawValue: 0x0100)
    }

    /// XCLC field: exterior grid slot. One cell spans 4096 game units.
    struct Grid: Equatable {
        let x: Int32
        let y: Int32
        /// Force-hide-land-quad bits 0x1-0x8; high bits carry CK noise
        /// (UESP notes they look random) — kept verbatim, masked by users.
        let quadFlags: UInt32
    }

    let formID: FormID
    let editorID: String?
    /// FULL — interior cells only in vanilla.
    let name: LString?
    let flags: Flags
    /// Present on exterior cells, nil on interiors.
    let grid: Grid?

    var isInterior: Bool {
        flags.contains(.interior)
    }

    /// - Parameter localized: TES4 localized flag of the owning plugin.
    init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "CELL" else {
            throw ESMError.malformed("expected CELL record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var name: LString?
        var flags: Flags = []
        var grid: Grid?
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "FULL":
                name = try LString(field: field, localized: localized)
            case "DATA":
                // uint16 in SSE; some records carry only one byte (UESP).
                flags = if field.data.count == 1 {
                    try Flags(rawValue: UInt16(reader.readUInt8()))
                } else {
                    try Flags(rawValue: reader.readUInt16())
                }
            case "XCLC":
                let x = try Int32(bitPattern: reader.readUInt32())
                let y = try Int32(bitPattern: reader.readUInt32())
                // Older (form version 43) records end after Y; the quad-flags
                // uint32 exists only in 12-byte fields.
                let quadFlags = try reader.bytesRemaining >= 4 ? reader.readUInt32() : 0
                grid = Grid(x: x, y: y, quadFlags: quadFlags)
            default:
                break
            }
        }
        self.editorID = editorID
        self.name = name
        self.flags = flags
        self.grid = grid
    }
}
