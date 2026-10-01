// REGN record. Each data area opens with an RDAT header. OpenSky decodes the
// weather area (RDAT 3, RDWT) and the sound area (RDAT 7, RDSA) and skips the
// rest. Layout from UESP and xEdit: docs/formats/weather.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public struct Region: Sendable {
    /// One RDWT entry. Same 12-byte layout as a CLMT WLST entry.
    public typealias WeatherChance = Climate.WeatherChance

    /// One RDSA entry under a sound (type 7) data area. Source of per-region
    /// ambient sound: xEdit wbRegionSounds (wbDefinitionsCommon.pas:8729-8747).
    /// Each entry is a 12-byte struct: SNDR (or SOUN legacy marker) FormID,
    /// weather-state filter flags, and a per-entry weight.
    public struct SoundEntry: Equatable, Sendable {
        /// Weather states under which this entry is eligible. Bit 0x01 = pleasant,
        /// 0x02 = cloudy, 0x04 = rainy, 0x08 = snowy. An empty set means the
        /// entry plays in all weather.
        public struct Conditions: OptionSet, Equatable, Sendable {
            public let rawValue: UInt32

            public init(rawValue: UInt32) {
                self.rawValue = rawValue
            }

            public static let pleasant = Conditions(rawValue: 0x0001)
            public static let cloudy = Conditions(rawValue: 0x0002)
            public static let rainy = Conditions(rawValue: 0x0004)
            public static let snowy = Conditions(rawValue: 0x0008)
        }

        /// SNDR (or SOUN legacy marker) FormID. The runtime resolves the
        /// SOUN.SDSC hop to its SNDR.
        public let sound: FormID
        public let conditions: Conditions
        /// Per-entry weight in the 0-1 range (probe against Skyrim.esm:
        /// min 0.01, max 1.0; the CK presents it as a percentage but the
        /// stored value is the 0-1 weight the runtime uses).
        public let chance: Float
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

    public let formID: FormID
    public let editorID: String?
    /// WNAM worldspace this region belongs to; nil when absent.
    public let worldspace: FormID?
    /// RCLR editor map color; nil when absent.
    public let mapColor: SIMD3<Float>?
    /// RDWT weather entries from the weather data area; empty when absent.
    public let weatherList: [WeatherChance]
    /// Weather area RDAT priority; nil when no weather area present.
    public let weatherPriority: Int?
    /// Weather area RDAT override flag (RDAT flags bit 0x01).
    public let weatherOverride: Bool
    /// RDSA entries from the sound data area; empty when absent.
    public let soundList: [SoundEntry]
    /// Sound area RDAT priority; nil when no sound area present.
    public let soundPriority: Int?
    /// Sound area RDAT override flag.
    public let soundOverride: Bool
    /// RDMO — region music type (MUSC). UESP REGN notes it "can appear
    /// with RDSA under same RDAT or on its own", so it is accepted regardless
    /// of the current area context. nil when absent or null.
    public let musicType: FormID?

    public init(record: ESMRecord) throws {
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
    /// complexity cap (RDSA, tipped it over).
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
                weatherList = try Climate.readWeatherList(
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
