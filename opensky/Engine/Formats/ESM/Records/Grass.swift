// GRAS record decoded into engine types: model path plus procedural placement
// controls referenced by LTEX GNAM entries.
//
// Reference: xEdit dev-4.1.5 wbDefinitionsTES5.pas (wbRecord(GRAS)):
//   https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.5/Core/wbDefinitionsTES5.pas
// Field meanings cross-checked against Creation Kit "Grass":
//   https://ck.uesp.net/wiki/Grass
// Layout + placement policy: docs/formats/grass.md.

import Foundation

nonisolated struct Grass: Equatable {
    /// DATA units-from-water rule. Unknown mod values stay representable so a
    /// future policy can support them without making the record undecodable.
    enum WaterRule: Equatable {
        case aboveAtLeast
        case aboveAtMost
        case belowAtLeast
        case belowAtMost
        case eitherAtLeast
        case eitherAtMost
        case eitherAtMostAbove
        case eitherAtMostBelow
        case unknown(UInt32)

        init(rawValue: UInt32) {
            self = switch rawValue {
            case 0: .aboveAtLeast
            case 1: .aboveAtMost
            case 2: .belowAtLeast
            case 3: .belowAtMost
            case 4: .eitherAtLeast
            case 5: .eitherAtMost
            case 6: .eitherAtMostAbove
            case 7: .eitherAtMostBelow
            default: .unknown(rawValue)
            }
        }
    }

    struct Flags: OptionSet, Equatable {
        let rawValue: UInt8

        static let vertexLighting = Flags(rawValue: 0x01)
        static let uniformScaling = Flags(rawValue: 0x02)
        static let fitToSlope = Flags(rawValue: 0x04)
    }

    /// Fixed 32-byte DATA body, kept separate from record identity/model.
    struct PlacementData: Equatable {
        let density: UInt8
        let minimumSlopeDegrees: UInt8
        let maximumSlopeDegrees: UInt8
        let unitsFromWater: UInt16
        let waterRule: WaterRule
        let positionRange: Float
        let heightRange: Float
        let colorRange: Float
        let wavePeriod: Float
        let flags: Flags
    }

    let formID: FormID
    let editorID: String?
    /// MODL — NIF path relative to Data/.
    let modelPath: String?
    /// DATA is required by xEdit; nil remains decodable so callers can
    /// reason-tag malformed mod records instead of losing record identity.
    let placement: PlacementData?

    init(record: ESMRecord) throws {
        guard record.type == "GRAS" else {
            throw ESMError.malformed("expected GRAS record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var modelPath: String?
        var placement: PlacementData?
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "MODL":
                modelPath = try reader.readZString()
            case "DATA":
                placement = try Self.decodePlacement(field.data)
            default:
                break
            }
        }
        self.editorID = editorID
        self.modelPath = modelPath
        self.placement = placement
    }

    /// xEdit wbGRAS DATA: 4 leading bytes, water u16 + padding, rule u32,
    /// four float controls, flags u8 + 3 padding = 32 bytes.
    private static func decodePlacement(_ data: Data) throws -> PlacementData {
        guard data.count == 32 else {
            throw ESMError.malformed("GRAS DATA size \(data.count), expected 32")
        }
        var reader = BinaryReader(data)
        let density = try reader.readUInt8()
        let minimumSlope = try reader.readUInt8()
        let maximumSlope = try reader.readUInt8()
        _ = try reader.readUInt8()
        let unitsFromWater = try reader.readUInt16()
        _ = try reader.readUInt16()
        let waterRule = try WaterRule(rawValue: reader.readUInt32())
        let positionRange = try reader.readFloat32()
        let heightRange = try reader.readFloat32()
        let colorRange = try reader.readFloat32()
        let wavePeriod = try reader.readFloat32()
        let flags = try Flags(rawValue: reader.readUInt8())
        _ = try reader.read(count: 3)
        return PlacementData(
            density: density,
            minimumSlopeDegrees: minimumSlope,
            maximumSlopeDegrees: maximumSlope,
            unitsFromWater: unitsFromWater,
            waterRule: waterRule,
            positionRange: positionRange,
            heightRange: heightRange,
            colorRange: colorRange,
            wavePeriod: wavePeriod,
            flags: flags
        )
    }
}
