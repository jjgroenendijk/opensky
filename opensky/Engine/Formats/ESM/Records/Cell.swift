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
    /// XCLR — REGN regions overlapping this exterior cell (empty on interiors
    /// and cells without XCLR). Feeds region weather selection (M7.2.2) and
    /// region ambient sound selection (M9.2.2).
    let regions: [FormID]
    /// XCAS — acoustic space (ASPC) reference, the interior-ambience hook
    /// (M9.2.2). Exterior cells generally carry none; interiors point at an
    /// ASPC whose SNAM/RDAT drive the per-cell ambient bed. nil when absent.
    let acousticSpace: FormID?
    /// XCMO — music type (MUSC) override for this cell (M9.2.3). nil when
    /// absent or null; the music director then falls back to the worldspace
    /// or region music.
    let musicType: FormID?
    /// XLCN — the LCTN containing this cell.
    let location: FormID?

    var isInterior: Bool {
        flags.contains(.interior)
    }

    /// - Parameter localized: TES4 localized flag of the owning plugin.
    init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "CELL" else {
            throw ESMError.malformed("expected CELL record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var fields = CellFields()
        for field in try record.fields() {
            try fields.decode(field: field, localized: localized)
        }
        editorID = fields.editorID
        name = fields.name
        flags = fields.flags
        grid = fields.grid
        waterHeight = fields.waterHeight
        waterType = fields.waterType
        lighting = fields.lighting
        lightingTemplate = fields.lightingTemplate
        regions = fields.regions
        acousticSpace = fields.acousticSpace
        musicType = fields.musicType
        location = fields.location
    }

    /// Mutable accumulator for the field loop. Split out so the field switch
    /// does not push init past the strict-lint cyclomatic-complexity cap
    /// (XCAS, added in M9.2.2, tipped it over).
    private struct CellFields {
        var editorID: String?
        var name: LString?
        var flags: Flags = []
        var grid: Grid?
        var waterHeight: WaterHeight?
        var waterType: FormID?
        var lighting: CellLightingValues?
        var lightingTemplate: FormID?
        var regions: [FormID] = []
        var acousticSpace: FormID?
        var musicType: FormID?
        var location: FormID?

        mutating func decode(field: ESMField, localized: Bool) throws {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "FULL":
                name = try LString(field: field, localized: localized)
            case "DATA":
                flags = try Cell.decodeFlags(&reader, count: field.data.count)
            case "XCLC":
                let x = try Int32(bitPattern: reader.readUInt32())
                let y = try Int32(bitPattern: reader.readUInt32())
                // Older (form version 43) records end after Y; the quad-flags
                // uint32 exists only in 12-byte fields.
                let quadFlags = try reader.bytesRemaining >= 4 ? reader.readUInt32() : 0
                grid = Grid(x: x, y: y, quadFlags: quadFlags)
            case "XCLW":
                waterHeight = try Cell.decodeWaterHeight(field.data)
            case "XCLL":
                lighting = try CellLightingValues.decode(field.data, hasInheritFlags: true)
            default:
                try decodeReference(field: field)
            }
        }

        /// Fields that are a plain FormID link or an array of them. Split out
        /// of `decode` so neither switch passes the strict-lint cyclomatic-
        /// complexity cap (XCMO, added in M9.2.3, tipped it over).
        private mutating func decodeReference(field: ESMField) throws {
            switch field.type {
            case "XCWT":
                waterType = try Cell.decodeFormID(field.data)
            case "LTMP":
                lightingTemplate = try Cell.decodeFormID(field.data)
            case "XCLR":
                // Array of 4-byte REGN FormIDs (xEdit wbArrayS XCLR 'Regions').
                // Non-multiple-of-4 payloads are skipped rather than guessed.
                regions = try Cell.decodeRegions(field.data)
            case "XCAS":
                // FormID into ASPC. xEdit wbDefinitionsTES5.pas:4376.
                acousticSpace = try Cell.decodeFormID(field.data)
            case "XCMO":
                // FormID into MUSC. xEdit wbDefinitionsTES5.pas:4378 +
                // UESP CELL. A null link means "no override".
                musicType = try Cell.decodeNonNullFormID(field.data)
            case "XLCN":
                // UESP CELL + xEdit wbDefinitionsTES5.pas: LCTN link.
                location = try Cell.decodeNonNullFormID(field.data)
            default:
                break
            }
        }
    }

    /// DATA flags: uint16 in SSE; some records carry only one byte (UESP).
    private static func decodeFlags(_ reader: inout BinaryReader, count: Int) throws -> Flags {
        if count == 1 {
            return try Flags(rawValue: UInt16(reader.readUInt8()))
        }
        return try Flags(rawValue: reader.readUInt16())
    }

    private static func decodeRegions(_ data: Data) throws -> [FormID] {
        guard data.count % 4 == 0, !data.isEmpty else { return [] }
        var reader = BinaryReader(data)
        var out: [FormID] = []
        out.reserveCapacity(data.count / 4)
        for _ in 0 ..< (data.count / 4) {
            try out.append(FormID(reader.readUInt32()))
        }
        return out
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

    /// Same as `decodeFormID` but folds an authored null link to nil, which is
    /// how the music override reads ("no override" rather than "form 0").
    private static func decodeNonNullFormID(_ data: Data) throws -> FormID? {
        guard let formID = try decodeFormID(data) else { return nil }
        return formID.isNull ? nil : formID
    }
}
