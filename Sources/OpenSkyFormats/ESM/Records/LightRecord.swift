// LIGH base-light decoder. DATA is the exact 48-byte Skyrim layout; point
// rendering currently accepts omni variants, skipping negative + spot.
//
// References:
// - UESP LIGH: https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/LIGH
// - xEdit dev-4.1.6 wbDefinitionsTES5.pas, LIGH DATA flag list

import Foundation
import simd

nonisolated package struct LightRecord {
    private struct DecodedData {
        let time: Int32
        let radius: UInt32
        let color: SIMD3<Float>
        let flags: Flags
        let falloff: Float
    }

    package struct Flags: OptionSet, Equatable {
        package let rawValue: UInt32

        package init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        package static let dynamic = Flags(rawValue: 0x0001)
        package static let canBeCarried = Flags(rawValue: 0x0002)
        package static let negative = Flags(rawValue: 0x0004)
        package static let flicker = Flags(rawValue: 0x0008)
        package static let offByDefault = Flags(rawValue: 0x0020)
        package static let flickerSlow = Flags(rawValue: 0x0040)
        package static let pulse = Flags(rawValue: 0x0080)
        package static let pulseSlow = Flags(rawValue: 0x0100)
        package static let spotLight = Flags(rawValue: 0x0200)
        package static let shadowSpotlight = Flags(rawValue: 0x0400)
        package static let shadowHemisphere = Flags(rawValue: 0x0800)
        package static let shadowOmnidirectional = Flags(rawValue: 0x1000)
        package static let portalStrict = Flags(rawValue: 0x2000)
        package static let inverseSquare = Flags(rawValue: 0x4000)
        package static let linear = Flags(rawValue: 0x8000)
    }

    package let formID: FormID
    package let editorID: String?
    package let time: Int32
    package let radius: UInt32
    package let color: SIMD3<Float>
    package let flags: Flags
    package let falloffExponent: Float
    package let fade: Float

    package var isSupportedPointLight: Bool {
        !flags.contains(.negative)
            && !flags.contains(.spotLight)
            && !flags.contains(.shadowSpotlight)
            && !flags.contains(.offByDefault)
    }

    package init(record: ESMRecord) throws {
        guard record.type == "LIGH" else {
            throw ESMError.malformed("expected LIGH record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var editorID: String?
        var decoded: DecodedData?
        var fade: Float = 1
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "DATA":
                guard field.data.count == 48 else {
                    throw ESMError.malformed(
                        "LIGH \(formID) DATA has \(field.data.count) bytes, expected 48"
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
                break
            }
        }
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
