// REGN record — milestone-7.2 scope is the weather list; milestone-9.2 adds
// the sound area. A region can hold several data areas (objects, map, grass,
// sound, weather), each introduced by an RDAT header and followed by area-
// specific fields that stream sequentially. OpenSky decodes the weather area
// (RDAT type 3 + RDWT) and the sound area (RDAT type 7 + RDSA); skips the rest.
//
// Reference: UESP "Skyrim Mod:Mod File Format/REGN"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/REGN
// xEdit dev-4.1.6 wbDefinitionsTES5.pas REGN body lines 9954-10041 +
// wbDefinitionsCommon.pas wbRegionSounds lines 8712-8748 (RDSA struct).
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

    /// One RDSA entry under a sound (type 7) data area. Source of per-region
    /// ambient sound: xEdit wbRegionSounds (wbDefinitionsCommon.pas:8729-8747).
    /// Each entry is a 12-byte struct: SNDR (or SOUN legacy marker) FormID,
    /// weather-state filter flags, and a per-entry weight.
    struct SoundEntry: Equatable {
        /// Weather states under which this entry is eligible. Bit 0x01 = pleasant,
        /// 0x02 = cloudy, 0x04 = rainy, 0x08 = snowy. An empty set means the
        /// entry plays in all weather.
        struct Conditions: OptionSet, Equatable {
            let rawValue: UInt32

            static let pleasant = Conditions(rawValue: 0x0001)
            static let cloudy = Conditions(rawValue: 0x0002)
            static let rainy = Conditions(rawValue: 0x0004)
            static let snowy = Conditions(rawValue: 0x0008)

            /// The bit set CK uses when "all weather" is selected.
            static let all: Conditions = [.pleasant, .cloudy, .rainy, .snowy]
        }

        /// SNDR (or SOUN legacy marker) FormID. The runtime resolves the
        /// SOUN.SDSC hop to its SNDR.
        let sound: FormID
        let conditions: Conditions
        /// Per-entry weight in the 0-1 range (probe against Skyrim.esm:
        /// min 0.01, max 1.0; the CK presents it as a percentage but the
        /// stored value is the 0-1 weight the runtime uses).
        let chance: Float
    }

    /// RDAT area type codes (uint32). Weather and sound are decoded.
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
    /// RDSA entries from the sound data area; empty when absent.
    let soundList: [SoundEntry]
    /// Sound area RDAT priority; nil when no sound area present.
    let soundPriority: Int?
    /// Sound area RDAT override flag.
    let soundOverride: Bool
    /// RDMO — region music type (MUSC), M9.2.3. UESP REGN notes it "can appear
    /// with RDSA under same RDAT or on its own", so it is accepted regardless
    /// of the current area context. nil when absent or null.
    let musicType: FormID?

    init(record: ESMRecord) throws {
        guard record.type == "REGN" else {
            throw ESMError.malformed("expected REGN record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var fields = RegionFields()
        for field in try record.fields() {
            try fields.decode(field: field)
        }
        editorID = fields.editorID
        worldspace = fields.worldspace
        mapColor = fields.mapColor
        weatherList = fields.weatherList
        weatherPriority = fields.weatherPriority
        weatherOverride = fields.weatherOverride
        soundList = fields.soundList
        soundPriority = fields.soundPriority
        soundOverride = fields.soundOverride
        musicType = fields.musicType
    }

    /// Mutable accumulator for the field loop. Split out so the area-aware
    /// field switch does not push init past the strict-lint cyclomatic-
    /// complexity cap (RDSA, added in M9.2.2, tipped it over).
    private struct RegionFields {
        var editorID: String?
        var worldspace: FormID?
        var mapColor: SIMD3<Float>?
        var weatherList: [WeatherChance] = []
        var weatherPriority: Int?
        var weatherOverride = false
        var soundList: [SoundEntry] = []
        var soundPriority: Int?
        var soundOverride = false
        var musicType: FormID?
        /// Last RDAT area type seen; area fields (RDWT, RDSA, ...) bind to it.
        var currentArea: AreaType?

        mutating func decode(field: ESMField) throws {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "WNAM":
                worldspace = try FormID(reader.readUInt32())
            case "RCLR":
                // 4-byte RGBX; skip unknown-size variants.
                guard field.data.count == 4 else { return }
                mapColor = try Region.readColor(&reader)
            case "RDAT":
                try applyRDAT(field: field, reader: &reader)
            case "RDWT":
                // Weather entries — only meaningful under a type-3 area.
                // Array of 12-byte structs: weather formid, uint32 chance,
                // global formid. Reject non-multiples rather than guess.
                guard currentArea == .weather, field.data.count % 12 == 0 else { return }
                weatherList = try Region.readWeatherList(
                    &reader, count: field.data.count / 12
                )
            case "RDSA":
                // Sound entries — only meaningful under a type-7 area.
                // Array of 12-byte structs: sound formid, uint32 flags,
                // float chance. Reject non-multiples rather than guess.
                guard currentArea == .sound, field.data.count % 12 == 0 else { return }
                soundList = try Region.readSoundList(
                    &reader, count: field.data.count / 12
                )
            case "RDMO":
                // Region music (MUSC). xEdit wbDefinitionsTES5.pas:9984.
                // Accepted outside the sound area on purpose (see `musicType`).
                musicType = Region.readMusicType(field.data) ?? musicType
            default:
                // Skipped: RPLI/RPLD (region point list), RDOT (objects),
                // RDMP (map name), RDGS (grass). Their payloads stream past
                // untouched.
                break
            }
        }

        private mutating func applyRDAT(
            field: ESMField, reader: inout BinaryReader
        ) throws {
            // 8-byte header: uint32 type, uint8 flags, uint8 priority,
            // uint16 always 0. Short header -> drop area context.
            guard field.data.count >= 8 else {
                currentArea = nil
                return
            }
            let type = try reader.readUInt32()
            let flags = try reader.readUInt8()
            let priority = try Int(reader.readUInt8())
            currentArea = AreaType(rawValue: type)
            if currentArea == .weather {
                weatherPriority = priority
                weatherOverride = flags & 0x01 != 0
            }
            if currentArea == .sound {
                soundPriority = priority
                soundOverride = flags & 0x01 != 0
            }
        }
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

    private static func readSoundList(
        _ reader: inout BinaryReader,
        count: Int
    ) throws -> [SoundEntry] {
        var entries: [SoundEntry] = []
        entries.reserveCapacity(count)
        for _ in 0 ..< count {
            let sound = try FormID(reader.readUInt32())
            let conditions = try SoundEntry.Conditions(rawValue: reader.readUInt32())
            let chance = try reader.readFloat32()
            entries.append(SoundEntry(
                sound: sound,
                conditions: conditions,
                chance: chance
            ))
        }
        return entries
    }

    /// 4-byte MUSC FormID. Wrong widths and null links yield nil so the caller
    /// keeps whatever a previous RDMO supplied.
    private static func readMusicType(_ data: Data) -> FormID? {
        guard data.count == 4 else { return nil }
        var reader = BinaryReader(data)
        guard let raw = try? reader.readUInt32() else { return nil }
        let formID = FormID(raw)
        return formID.isNull ? nil : formID
    }

    private static func readColor(_ reader: inout BinaryReader) throws -> SIMD3<Float> {
        let red = try Float(reader.readUInt8()) / 255
        let green = try Float(reader.readUInt8()) / 255
        let blue = try Float(reader.readUInt8()) / 255
        _ = try reader.readUInt8() // RGBX padding
        return SIMD3(red, green, blue)
    }
}
