// CELL record decoded into engine types: flags, exterior grid coordinates, and
// display name, for interior and exterior cells. References live in the child
// group after the record. Layout: docs/formats/world-records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct Cell: Sendable {
    /// XCLW override. Missing field means use WRLD DNAM; three known bit
    /// patterns mean explicitly no water and must not fall back to WRLD.
    public enum WaterHeight: Equatable, Sendable {
        case height(Float)
        case noWater
    }

    /// DATA field (uint16; one byte in some records — see init).
    public struct Flags: OptionSet, Sendable {
        public let rawValue: UInt16

        public init(rawValue: UInt16) {
            self.rawValue = rawValue
        }

        public static let interior = Flags(rawValue: 0x0001)
        public static let hasWater = Flags(rawValue: 0x0002)
        public static let noLODWater = Flags(rawValue: 0x0008)
        public static let showSky = Flags(rawValue: 0x0080)
        public static let useSkyLighting = Flags(rawValue: 0x0100)
    }

    /// XCLC field: exterior grid slot. One cell spans 4096 game units.
    public struct Grid: Equatable, Sendable {
        public let x: Int32
        public let y: Int32
        /// Force-hide-land-quad bits 0x1-0x8; high bits carry CK noise
        /// (UESP notes they look random) — kept verbatim, masked by users.
        public let quadFlags: UInt32
    }

    public internal(set) var formID: FormID
    public let editorID: String?
    /// FULL — interior cells only in vanilla.
    public let name: LString?
    public let flags: Flags
    /// Present on exterior cells, nil on interiors.
    public let grid: Grid?
    /// XCLW. nil = inherit WRLD DNAM default water height.
    public let waterHeight: WaterHeight?
    /// XCWT per-cell WATR override. nil = use WRLD NAM2.
    public internal(set) var waterType: FormID?
    /// XCLL cell-local lighting values; nil when absent or too truncated.
    public let lighting: CellLightingValues?
    /// LTMP -> LGTM lighting template.
    public internal(set) var lightingTemplate: FormID?
    /// XCLR — REGN regions overlapping this exterior cell (empty on interiors
    /// and cells without XCLR). Feeds region weather and
    /// ambient sound selection.
    public internal(set) var regions: [FormID]
    /// XCAS — acoustic space (ASPC) reference, the interior-ambience hook.
    /// Exterior cells generally carry none; interiors point at an ASPC whose SNAM/RDAT drive the
    /// per-cell ambient bed. nil when absent.
    public internal(set) var acousticSpace: FormID?
    /// XCMO — music type (MUSC) override for this cell. nil when
    /// absent or null; the music director then falls back to the worldspace
    /// or region music.
    public internal(set) var musicType: FormID?
    /// XLCN — the LCTN containing this cell.
    public internal(set) var location: FormID?
    /// XEZN — the ECZN governing this cell's encounter level and reset data.
    public internal(set) var encounterZone: FormID?
    /// XOWN — the NPC_ or FACT that owns everything in this cell, which is what
    /// a reference with no `XOWN` of its own inherits. nil when
    /// the cell is unowned, which is the normal state for a dungeon and for the
    /// player's own house.
    public internal(set) var owner: FormID?
    /// XRNK — the faction rank a member needs before the cell's contents are
    /// theirs to use. Meaningful only when `owner` names a FACT; nil when the
    /// field is absent, which is every vanilla cell observed on this install.
    public let ownerFactionRank: Int32?
    /// The fields that rarely matter to the engine: water extras, occlusion, height data.
    public internal(set) var extras: CellExtras
    public let skipped: FieldTally

    public var isInterior: Bool {
        flags.contains(.interior)
    }

    /// - Parameter localized: TES4 localized flag of the owning plugin.
    public init(record: ESMRecord, localized: Bool) throws {
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
        encounterZone = fields.encounterZone
        owner = fields.owner
        ownerFactionRank = fields.ownerFactionRank
        extras = fields.extras
        skipped = fields.skipped
    }

    /// Mutable accumulator for the field loop. Split out so the field switch
    /// does not push init past the strict-lint cyclomatic-complexity cap
    /// (XCAS, tipped it over).
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
        var encounterZone: FormID?
        var owner: FormID?
        var ownerFactionRank: Int32?
        var extras = CellExtras()
        var skipped = FieldTally()

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
        /// complexity cap (XCMO, tipped it over).
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
            case "XEZN":
                // UESP CELL + xEdit wbDefinitionsTES5.pas: ECZN link.
                encounterZone = try Cell.decodeNonNullFormID(field.data)
            case "XOWN":
                // UESP CELL "XOWN — Owner (NPC_ or FACT)" + xEdit
                // wbDefinitionsTES5.pas, which models the CELL owner exactly as
                // it models a REFR's. Observed on this install: every owned
                // Whiterun interior carries a 4-byte XOWN and none carries an
                // XRNK.
                owner = try Cell.decodeNonNullFormID(field.data)
            case "XRNK":
                // xEdit wbDefinitionsTES5.pas `wbXRNK`: int32 faction rank,
                // meaningful only beside a FACT owner. Decoded defensively —
                // no vanilla CELL was observed carrying one.
                ownerFactionRank = try Cell.decodeInt32(field.data)
            default:
                if try !extras.decode(field: field) {
                    skipped.note(.unknownField(field.type))
                }
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

    /// XRNK, a signed 32-bit rank. A field too short to hold one degrades to
    /// "not set" rather than throwing, the rule `PlacedReference` follows for
    /// the same subrecord.
    private static func decodeInt32(_ data: Data) throws -> Int32? {
        guard data.count >= 4 else { return nil }
        var reader = BinaryReader(data)
        return try Int32(bitPattern: reader.readUInt32())
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
