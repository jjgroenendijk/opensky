// WRLD record decoded into engine types: editor ID, name, parent link, flags,
// and the DNAM default land and water heights. Exterior cells follow in the
// world children group. Layout: docs/formats/world-records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct Worldspace: Sendable {
    /// PNAM flags attached to WNAM. A set bit means use that data category
    /// from the parent worldspace rather than local fields.
    public struct ParentFlags: OptionSet, Sendable {
        public let rawValue: UInt16

        public init(rawValue: UInt16) {
            self.rawValue = rawValue
        }

        public static let useLandData = ParentFlags(rawValue: 0x0001)
        public static let useWaterData = ParentFlags(rawValue: 0x0008)
    }

    /// DATA field (uint8).
    public struct Flags: OptionSet, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let smallWorld = Flags(rawValue: 0x01)
        public static let noFastTravel = Flags(rawValue: 0x02)
        public static let noLODWater = Flags(rawValue: 0x08)
        public static let noLandscape = Flags(rawValue: 0x10)
        public static let noSky = Flags(rawValue: 0x20)
        public static let fixedDimensions = Flags(rawValue: 0x40)
        public static let noGrass = Flags(rawValue: 0x80)
    }

    public let formID: FormID
    /// EDID (e.g. "Tamriel"). Present on all vanilla worldspaces.
    public let editorID: String?
    /// FULL — in-game name ("Skyrim").
    public let name: LString?
    /// WNAM — parent worldspace this one inherits data from.
    public let parent: FormID?
    /// PNAM — categories inherited from `parent`.
    public let parentFlags: ParentFlags
    public let flags: Flags
    /// DNAM first float — default land height for cells without a LAND record
    /// (Tamriel reads -27000). Nil when the record carries no DNAM.
    public let defaultLandHeight: Float?
    /// DNAM second float — default water height (Tamriel reads -14000). Nil
    /// when the record carries no DNAM.
    public let defaultWaterHeight: Float?
    /// NAM2 — default WATR record for cells without XCWT.
    public let waterType: FormID?
    /// CNAM — default CLMT climate for this worldspace; the weather runtime's
    /// climate fallback when no region weather applies. nil when absent.
    public let climate: FormID?
    /// ZNAM — default music type (MUSC) for this worldspace. The
    /// music director's fallback when the cell carries no XCMO and no region
    /// music applies. nil when absent or null.
    public let musicType: FormID?
    /// XEZN — default encounter zone for the worldspace.
    public let encounterZone: FormID?

    /// - Parameter localized: TES4 localized flag of the owning plugin
    ///   (`PluginHeader.isLocalized`) — decides lstring decoding.
    public init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "WRLD" else {
            throw ESMError.malformed("expected WRLD record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var fields = WorldspaceFields()
        for field in try record.fields() {
            try fields.decode(field: field, localized: localized)
        }
        editorID = fields.editorID
        name = fields.name
        parent = fields.parent
        parentFlags = fields.parentFlags
        flags = fields.flags
        defaultLandHeight = fields.defaultLandHeight
        defaultWaterHeight = fields.defaultWaterHeight
        waterType = fields.waterType
        climate = fields.climate
        musicType = fields.musicType
        encounterZone = fields.encounterZone
    }

    /// Mutable accumulator for the field loop, matching `Cell`/`Region`. Split
    /// out so the field switch stays under the strict-lint cyclomatic-
    /// complexity cap (ZNAM, tipped it over).
    private struct WorldspaceFields {
        var editorID: String?
        var name: LString?
        var parent: FormID?
        var parentFlags: ParentFlags = []
        var flags: Flags = []
        var defaultLandHeight: Float?
        var defaultWaterHeight: Float?
        var waterType: FormID?
        var climate: FormID?
        var musicType: FormID?
        var encounterZone: FormID?

        mutating func decode(field: ESMField, localized: Bool) throws {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "FULL":
                name = try LString(field: field, localized: localized)
            case "WNAM":
                parent = try FormID(reader.readUInt32())
            case "PNAM":
                parentFlags = try Worldspace.decodeParentFlags(field.data) ?? parentFlags
            case "DATA":
                flags = try Flags(rawValue: reader.readUInt8())
            case "DNAM":
                // 8 bytes: float default land height, float default water
                // height (UESP WRLD). Undersized modder DNAM -> left nil.
                if field.data.count >= 8 {
                    defaultLandHeight = try reader.readFloat32()
                    defaultWaterHeight = try reader.readFloat32()
                }
            default:
                try decodeReference(field: field)
            }
        }

        /// Fields that are a plain FormID link.
        private mutating func decodeReference(field: ESMField) throws {
            switch field.type {
            case "NAM2":
                waterType = try Worldspace.decodeFormID(field.data)
            case "CNAM":
                // WRLD CNAM: climate FormID (xEdit wbFormIDCk(CNAM, 'Climate')).
                climate = try Worldspace.decodeFormID(field.data)
            case "ZNAM":
                // WRLD ZNAM: default music type (xEdit wbDefinitionsTES5.pas:
                // 10772, wbFormIDCk(ZNAM, 'Music', [MUSC]); UESP WRLD "always
                // a MUSC form ID"). A null link means no worldspace music.
                musicType = try Worldspace.decodeNonNullFormID(field.data)
            case "XEZN":
                // xEdit wbDefinitionsTES5.pas `wbRecord(WRLD, ...)`: ECZN.
                encounterZone = try Worldspace.decodeNonNullFormID(field.data)
            default:
                break
            }
        }
    }

    private static func decodeParentFlags(_ data: Data) throws -> ParentFlags? {
        guard data.count >= 2 else { return nil }
        var reader = BinaryReader(data)
        return try ParentFlags(rawValue: reader.readUInt16())
    }

    private static func decodeFormID(_ data: Data) throws -> FormID? {
        guard data.count >= 4 else { return nil }
        var reader = BinaryReader(data)
        return try FormID(reader.readUInt32())
    }

    /// Same as `decodeFormID` but folds an authored null link to nil.
    private static func decodeNonNullFormID(_ data: Data) throws -> FormID? {
        guard let formID = try decodeFormID(data) else { return nil }
        return formID.isNull ? nil : formID
    }
}
