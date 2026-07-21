// CLMT record decoded into engine types: a climate binds a weather list (with
// per-weather chances), day/night timing, and sky textures the sky renderer
// draws. OpenSky reads the milestone-7.2 scope only: weather chances + timing;
// sun/glare/night-sky paths come along since they are trivial zstrings.
//
// Reference: UESP "Skyrim Mod:Mod File Format/CLMT"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CLMT
// Layout documented in docs/formats/weather.md.

import Foundation

nonisolated struct Climate {
    /// One WLST entry: weather that can occur under this climate + its chance.
    struct WeatherChance: Equatable {
        let weather: FormID
        /// Chance in percent (WLST chances sum to 100 across the list).
        let chance: Int
        /// Optional GLOB that scales the chance; nil when the FormID is null.
        let global: FormID?
    }

    /// TNAM timing + moon phase, decoded from the packed 6-byte struct.
    struct Timing: Equatable {
        /// Minutes past midnight (raw uint8 x 10).
        let sunriseBegin: Int
        let sunriseEnd: Int
        let sunsetBegin: Int
        let sunsetEnd: Int
        /// 0-100.
        let volatility: Int
        /// Raw moons byte: phase length (bits 0-5) + masser/secunda flags.
        let moons: UInt8
        /// Moon phase length in days (mask 0x3F).
        var phaseLengthDays: Int {
            Int(moons & 0x3F)
        }

        /// Masser present (bit 0x40).
        var masser: Bool {
            moons & 0x40 != 0
        }

        /// Secunda present (bit 0x80).
        var secunda: Bool {
            moons & 0x80 != 0
        }
    }

    let formID: FormID
    let editorID: String?
    /// WLST weather list; empty when absent.
    let weatherList: [WeatherChance]
    /// TNAM sun/moon timing; nil when absent or wrong-size.
    let timing: Timing?
    /// FNAM sun texture path.
    let sunTexture: String?
    /// GNAM sun glare texture path.
    let glareTexture: String?
    /// MODL night-sky model path (MODT skipped).
    let nightSkyModel: String?

    init(record: ESMRecord) throws {
        guard record.type == "CLMT" else {
            throw ESMError.malformed("expected CLMT record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var weatherList: [WeatherChance] = []
        var timing: Timing?
        var sunTexture: String?
        var glareTexture: String?
        var nightSkyModel: String?
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "WLST":
                // Array of 12-byte structs: weather formid, uint32 chance,
                // global formid. Reject non-multiples rather than guess.
                guard field.data.count % 12 == 0 else { continue }
                weatherList = try Self.readWeatherList(&reader, count: field.data.count / 12)
            case "TNAM":
                // 6-byte struct; skip unknown-size variants.
                guard field.data.count == 6 else { continue }
                timing = try Self.readTiming(&reader)
            case "FNAM":
                sunTexture = try reader.readZString()
            case "GNAM":
                glareTexture = try reader.readZString()
            case "MODL":
                nightSkyModel = try reader.readZString()
            default:
                // Skipped: MODT (model textures) — not needed at this scope.
                break
            }
        }
        self.editorID = editorID
        self.weatherList = weatherList
        self.timing = timing
        self.sunTexture = sunTexture
        self.glareTexture = glareTexture
        self.nightSkyModel = nightSkyModel
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

    private static func readTiming(_ reader: inout BinaryReader) throws -> Timing {
        let sunriseBegin = try Int(reader.readUInt8()) * 10
        let sunriseEnd = try Int(reader.readUInt8()) * 10
        let sunsetBegin = try Int(reader.readUInt8()) * 10
        let sunsetEnd = try Int(reader.readUInt8()) * 10
        let volatility = try Int(reader.readUInt8())
        let moons = try reader.readUInt8()
        return Timing(
            sunriseBegin: sunriseBegin,
            sunriseEnd: sunriseEnd,
            sunsetBegin: sunsetBegin,
            sunsetEnd: sunsetEnd,
            volatility: volatility,
            moons: moons
        )
    }
}
