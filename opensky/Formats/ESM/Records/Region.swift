// REGN record — milestone-7.2 scope is the weather list only. A region can hold
// several data areas (objects, map, grass, sound, weather), each introduced by
// an RDAT header and followed by area-specific fields that stream sequentially.
// OpenSky decodes the weather area (RDAT type 3 + RDWT) and skips the rest.
//
// Reference: UESP "Skyrim Mod:Mod File Format/REGN"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/REGN
// Layout documented in docs/formats/weather.md.

import Foundation
import simd

nonisolated struct Region {
    /// One RDWT entry under a weather (type 3) data area.
    struct WeatherChance: Equatable {
        let weather: FormID
        /// Chance in percent (entries sum to 100 across the area).
        let chance: Int
        /// Optional GLOB (unused by the game); nil when the FormID is null.
        let global: FormID?
    }

    /// RDAT area type codes (uint32). Only weather is decoded.
    private enum AreaType: UInt32 {
        case objects = 2
        case weather = 3
        case map = 4
        case landscape = 5
        case grass = 6
        case sound = 7
    }

    let formID: FormID
    let editorID: String?
    /// WNAM worldspace this region belongs to; nil when absent.
    let worldspace: FormID?
    /// RCLR editor map color; nil when absent.
    let mapColor: SIMD3<Float>?
    /// RDWT weather entries from the weather data area; empty when absent.
    let weatherList: [WeatherChance]
    /// Weather area RDAT priority; nil when no weather area present.
    let weatherPriority: Int?
    /// Weather area RDAT override flag (RDAT flags bit 0x01).
    let weatherOverride: Bool

    init(record: ESMRecord) throws {
        guard record.type == "REGN" else {
            throw ESMError.malformed("expected REGN record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var worldspace: FormID?
        var mapColor: SIMD3<Float>?
        var weatherList: [WeatherChance] = []
        var weatherPriority: Int?
        var weatherOverride = false
        // Last RDAT area type seen; area fields (RDWT, RDOT, ...) bind to it.
        var currentArea: AreaType?

        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "WNAM":
                worldspace = try FormID(reader.readUInt32())
            case "RCLR":
                // 4-byte RGBX; skip unknown-size variants.
                guard field.data.count == 4 else { continue }
                mapColor = try Self.readColor(&reader)
            case "RDAT":
                // 8-byte header: uint32 type, uint8 flags, uint8 priority,
                // uint16 always 0. Short header -> drop area context.
                guard field.data.count >= 8 else {
                    currentArea = nil
                    continue
                }
                let type = try reader.readUInt32()
                let flags = try reader.readUInt8()
                let priority = try Int(reader.readUInt8())
                currentArea = AreaType(rawValue: type)
                if currentArea == .weather {
                    weatherPriority = priority
                    weatherOverride = flags & 0x01 != 0
                }
            case "RDWT":
                // Weather entries — only meaningful under a type-3 area.
                // Array of 12-byte structs: weather formid, uint32 chance,
                // global formid. Reject non-multiples rather than guess.
                guard currentArea == .weather, field.data.count % 12 == 0 else { continue }
                weatherList = try Self.readWeatherList(&reader, count: field.data.count / 12)
            default:
                // Skipped: RPLI/RPLD (region point list), RDOT (objects),
                // RDMP (map name), RDGS (grass), RDSA/RDMO/RDMD (sound) — out
                // of scope; their payloads stream past untouched.
                break
            }
        }
        self.editorID = editorID
        self.worldspace = worldspace
        self.mapColor = mapColor
        self.weatherList = weatherList
        self.weatherPriority = weatherPriority
        self.weatherOverride = weatherOverride
    }

    private static func readWeatherList(
        _ reader: inout BinaryReader,
        count: Int
    ) throws -> [WeatherChance] {
        var entries: [WeatherChance] = []
        entries.reserveCapacity(count)
        for _ in 0 ..< count {
            let weather = try FormID(reader.readUInt32())
            let chance = try Int(reader.readUInt32())
            let global = try FormID(reader.readUInt32())
            entries.append(WeatherChance(
                weather: weather,
                chance: chance,
                global: global.isNull ? nil : global
            ))
        }
        return entries
    }

    private static func readColor(_ reader: inout BinaryReader) throws -> SIMD3<Float> {
        let red = try Float(reader.readUInt8()) / 255
        let green = try Float(reader.readUInt8()) / 255
        let blue = try Float(reader.readUInt8()) / 255
        _ = try reader.readUInt8() // RGBX padding
        return SIMD3(red, green, blue)
    }
}
