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
    /// XCLW override. Missing field means use WRLD DNAM; three known bit
    /// patterns mean explicitly no water and must not fall back to WRLD.
    enum WaterHeight: Equatable {
        case height(Float)
        case noWater
    }

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
    /// XCLW. nil = inherit WRLD DNAM default water height.
    let waterHeight: WaterHeight?
    /// XCWT per-cell WATR override. nil = use WRLD NAM2.
    let waterType: FormID?
    /// XCLL cell-local lighting values; nil when absent or too truncated.
    let lighting: CellLightingValues?
    /// LTMP -> LGTM lighting template.
    let lightingTemplate: FormID?

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
        var waterHeight: WaterHeight?
        var waterType: FormID?
        var lighting: CellLightingValues?
        var lightingTemplate: FormID?
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
            case "XCLW":
                waterHeight = try Self.decodeWaterHeight(field.data)
            case "XCWT":
                waterType = try Self.decodeFormID(field.data)
            case "XCLL":
                lighting = try CellLightingValues.decode(field.data, hasInheritFlags: true)
            case "LTMP":
                lightingTemplate = try Self.decodeFormID(field.data)
            default:
                break
            }
        }
        self.editorID = editorID
        self.name = name
        self.flags = flags
        self.grid = grid
        self.waterHeight = waterHeight
        self.waterType = waterType
        self.lighting = lighting
        self.lightingTemplate = lightingTemplate
    }

    private static func decodeWaterHeight(_ data: Data) throws -> WaterHeight? {
        guard data.count >= 4 else { return nil }
        var reader = BinaryReader(data)
        let bits = try reader.readUInt32()
        // UESP CELL + xEdit wbDefinitionsTES5.pas. 0x7F7FFFFF is
        // the documented default/no-water sentinel; the other two
        // are known CK-bug encodings with the same meaning.
        return switch bits {
        case 0x7F7F_FFFF, 0x4F7F_FFC9, 0xCF00_0000: .noWater
        default: .height(Float(bitPattern: bits))
        }
    }

    private static func decodeFormID(_ data: Data) throws -> FormID? {
        guard data.count >= 4 else { return nil }
        var reader = BinaryReader(data)
        return try FormID(reader.readUInt32())
    }
}
