// CLMT decoder coverage over synthetic field bytes only. Layout source:
// UESP "Skyrim Mod:Mod File Format/CLMT"; see docs/formats/records.md.

import Foundation
@testable import opensky
import Testing

struct ClimateRecordTests {
    @Test func decodesWeatherListTimingAndTextures() throws {
        var wlst = Data()
        // Entry 1: weather 0x10, 60%, global 0x20.
        wlst.appendUInt32(0x10)
        wlst.appendUInt32(60)
        wlst.appendUInt32(0x20)
        // Entry 2: weather 0x11, 40%, null global.
        wlst.appendUInt32(0x11)
        wlst.appendUInt32(40)
        wlst.appendUInt32(0)

        // TNAM: sunrise 3/5, sunset 78/82 (x10 min), volatility 25,
        // moons 0xC1 -> phase length 1 day, masser + secunda set.
        let tnam = Data([3, 5, 78, 82, 25, 0xC1])

        let fields = ESMFixture.field("EDID", ESMFixture.zstring("TestClimate"))
            + ESMFixture.field("WLST", wlst)
            + ESMFixture.field("FNAM", ESMFixture.zstring("Sky\\Sun.dds"))
            + ESMFixture.field("GNAM", ESMFixture.zstring("Sky\\Glare.dds"))
            + ESMFixture.field("MODL", ESMFixture.zstring("Sky\\Stars.nif"))
            + ESMFixture.field("TNAM", tnam)
        let climate = try Climate(record: record(ESMFixture.record(
            "CLMT", formID: 0x30, data: fields
        )))

        #expect(climate.formID == FormID(0x30))
        #expect(climate.editorID == "TestClimate")
        #expect(climate.sunTexture == "Sky\\Sun.dds")
        #expect(climate.glareTexture == "Sky\\Glare.dds")
        #expect(climate.nightSkyModel == "Sky\\Stars.nif")

        #expect(climate.weatherList == [
            Climate.WeatherChance(weather: FormID(0x10), chance: 60, global: FormID(0x20)),
            Climate.WeatherChance(weather: FormID(0x11), chance: 40, global: nil)
        ])

        let timing = try #require(climate.timing)
        #expect(timing.sunriseBegin == 30)
        #expect(timing.sunriseEnd == 50)
        #expect(timing.sunsetBegin == 780)
        #expect(timing.sunsetEnd == 820)
        #expect(timing.volatility == 25)
        #expect(timing.moons == 0xC1)
        #expect(timing.phaseLengthDays == 1)
        #expect(timing.masser)
        #expect(timing.secunda)
    }

    @Test func skipsWeatherListWithBadSize() throws {
        // 13 bytes: not a multiple of 12 -> whole WLST rejected.
        let fields = ESMFixture.field("WLST", Data(count: 13))
        let climate = try Climate(record: record(ESMFixture.record("CLMT", data: fields)))
        #expect(climate.weatherList.isEmpty)
    }

    @Test func missingFieldsDecodeToEmptyAndNil() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("Bare"))
        let climate = try Climate(record: record(ESMFixture.record("CLMT", data: fields)))
        #expect(climate.editorID == "Bare")
        #expect(climate.weatherList.isEmpty)
        #expect(climate.timing == nil)
        #expect(climate.sunTexture == nil)
    }

    @Test func wrongRecordTypeThrows() throws {
        #expect(throws: ESMError.self) {
            _ = try Climate(record: record(ESMFixture.record("WTHR", data: Data())))
        }
    }

    private func record(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }
}
