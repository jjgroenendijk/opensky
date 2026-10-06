// LIGH base-light decoder. DATA is the exact 48-byte Skyrim layout; point
// rendering currently accepts omni variants, skipping negative + spot.
//
// References:
// - UESP LIGH: https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/LIGH
// - xEdit dev-4.1.6 wbDefinitionsTES5.pas, LIGH DATA flag list

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public struct LightRecord: Sendable {
    private struct DecodedData {
        let time: Int32
        let radius: UInt32
        let color: SIMD3<Float>
        let flags: Flags
        let falloff: Float
    }

    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public static let negative = Flags(rawValue: 0x0004)
        public static let offByDefault = Flags(rawValue: 0x0020)
        public static let spotLight = Flags(rawValue: 0x0200)
        public static let shadowSpotlight = Flags(rawValue: 0x0400)
        public static let inverseSquare = Flags(rawValue: 0x4000)
    }

    public let formID: FormID
    public let editorID: String?
    public let time: Int32
    public let radius: UInt32
    public let color: SIMD3<Float>
    public let flags: Flags
    public let falloffExponent: Float
    public let fade: Float

    public var isSupportedPointLight: Bool {
        !flags.contains(.negative)
            && !flags.contains(.spotLight)
            && !flags.contains(.shadowSpotlight)
            && !flags.contains(.offByDefault)
    }

    /// The fields lighting does not read: model, name, sound, scripts.
    public let details: LightDetails
    public let skipped: FieldTally

    /// Decodes with FULL read as inline text.
    public init(record: ESMRecord) throws {
        try self.init(record: record, localized: false)
    }

    public init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "LIGH" else {
            throw ESMError.malformed("expected LIGH record, got \(record.type)")
        }
        var rest = try RecordFields(record: record, type: "LIGH", localized: localized)
        let recordID = rest.formID
        formID = recordID
        var editorID: String?
        var decoded: DecodedData?
        var fade: Float = 1
        try rest.readEach { field in
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "DATA":
                guard field.data.count == 48 else {
                    throw ESMError.malformed(
                        "LIGH \(recordID) DATA has \(field.data.count) bytes, expected 48"
                    )
                }
                let time = try Int32(bitPattern: reader.readUInt32())
                let radius = try reader.readUInt32()
                let color = try Self.readColor(&reader)
                let flags = try Flags(rawValue: reader.readUInt32())
                let falloff = try reader.readFloat32()
                reader.skip(28)
                decoded = DecodedData(
                    time: time,
                    radius: radius,
                    color: color,
                    flags: flags,
                    falloff: falloff
                )
            case "FNAM":
                if field.data.count >= 4 {
                    fade = try reader.readFloat32()
                }
            default:
                return false
            }
            return true
        }
        details = LightDetails(&rest)
        skipped = rest.finish()
        guard let decoded else {
            throw ESMError.malformed("LIGH \(formID) has no DATA field")
        }
        self.editorID = editorID
        time = decoded.time
        radius = decoded.radius
        color = decoded.color
        flags = decoded.flags
        falloffExponent = decoded.falloff
        self.fade = fade
    }

    private static func readColor(_ reader: inout BinaryReader) throws -> SIMD3<Float> {
        let red = try Float(reader.readUInt8()) / 255
        let green = try Float(reader.readUInt8()) / 255
        let blue = try Float(reader.readUInt8()) / 255
        _ = try reader.readUInt8()
        return SIMD3(red, green, blue)
    }
}

/// LIGH fields beyond the light itself; a carriable torch uses most of them.
/// xEdit dev-4.1.6 `LIGH`.
nonisolated public struct LightDetails: Equatable, Sendable {
    public let bounds: ObjectBounds?
    public let model: ModelData?
    /// FULL — the name of a carriable light.
    public let name: LString?
    public let iconPath: String?
    public let messageIconPath: String?
    /// SNAM — the SNDR the light loops.
    public let sound: FormID?
    /// LNAM — lens flare.
    public let lensFlare: FormID?
    public let destructible: Destructible?
    public let scriptData: ScriptData

    init(_ fields: inout RecordFields) {
        bounds = fields.bounds()
        model = fields.model()
        name = fields.lstring("FULL")
        iconPath = fields.zstring("ICON")
        messageIconPath = fields.zstring("MICO")
        sound = fields.formID("SNAM")
        lensFlare = fields.formID("LNAM")
        destructible = fields.destructible()
        scriptData = fields.scriptData()
    }
}
