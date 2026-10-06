// CLMT: a climate's weather list with chances, its day and night timing, and
// its sky textures. Source: UESP "Skyrim Mod:Mod File Format/CLMT".
// Layout: docs/formats/weather.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct Climate: Sendable {
    /// One WLST entry: weather that can occur under this climate + its chance.
    public struct WeatherChance: Equatable, Sendable {
        public let weather: FormID
        /// Chance in percent; the chances in one list sum to 100.
        public let chance: Int
        /// Optional GLOB that scales the chance; nil when the FormID is null.
        /// The game ignores it in a REGN RDWT entry.
        public let global: FormID?
    }

    /// TNAM timing + moon phase, decoded from the packed 6-byte struct.
    public struct Timing: Equatable, Sendable {
        /// Minutes past midnight (raw uint8 x 10).
        public let sunriseBegin: Int
        public let sunriseEnd: Int
        public let sunsetBegin: Int
        public let sunsetEnd: Int
        /// 0-100.
        public let volatility: Int
        /// Raw moons byte: phase length (bits 0-5) + masser/secunda flags.
        public let moons: UInt8
        /// Moon phase length in days (mask 0x3F).
        public var phaseLengthDays: Int {
            Int(moons & 0x3F)
        }

        /// Masser present (bit 0x40).
        public var masser: Bool {
            moons & 0x40 != 0
        }

        /// Secunda present (bit 0x80).
        public var secunda: Bool {
            moons & 0x80 != 0
        }
    }

    public let formID: FormID
    public let editorID: String?
    /// WLST weather list; empty when absent.
    public let weatherList: [WeatherChance]
    /// TNAM sun/moon timing; nil when absent or wrong-size.
    public let timing: Timing?
    /// FNAM sun texture path.
    public let sunTexture: String?
    /// GNAM sun glare texture path.
    public let glareTexture: String?
    /// MODL night-sky model path (MODT skipped).
    public let nightSkyModel: String?
    /// MODT of the night sky model, raw.
    public let nightSkyTextureHashes: Data?
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        guard record.type == "CLMT" else {
            throw ESMError.malformed("expected CLMT record, got \(record.type)")
        }
        var rest = try RecordFields(record: record, type: "CLMT")
        let recordID = rest.formID
        formID = recordID

        var editorID: String?
        var weatherList: [WeatherChance] = []
        var timing: Timing?
        var sunTexture: String?
        var glareTexture: String?
        var nightSkyModel: String?
        try rest.readEach { field in
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "WLST":
                // Array of 12-byte structs: weather formid, uint32 chance,
                // global formid. Reject non-multiples rather than guess.
                guard field.data.count % 12 == 0 else { return true }
                weatherList = try Self.readWeatherList(&reader, count: field.data.count / 12)
            case "TNAM":
                // 6-byte struct; skip unknown-size variants.
                guard field.data.count == 6 else { return true }
                timing = try Self.readTiming(&reader)
            case "FNAM":
                sunTexture = try reader.readZString()
            case "GNAM":
                glareTexture = try reader.readZString()
            case "MODL":
                nightSkyModel = try reader.readZString()
            default:
                return false
            }
            return true
        }
        nightSkyTextureHashes = rest.bytes("MODT")
        skipped = rest.finish()
        self.editorID = editorID
        self.weatherList = weatherList
        self.timing = timing
        self.sunTexture = sunTexture
        self.glareTexture = glareTexture
        self.nightSkyModel = nightSkyModel
    }

    /// Reads `count` 12-byte entries: weather FormID, uint32 chance, global FormID.
    static func readWeatherList(
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
