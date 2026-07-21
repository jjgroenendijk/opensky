// REGN decoder coverage over synthetic field bytes only. Layout source:
// UESP "Skyrim Mod:Mod File Format/REGN"; see docs/formats/records.md.

import Foundation
@testable import opensky
import Testing

struct RegionRecordTests {
    @Test func decodesOnlyWeatherAreaAmongMixedRDAT() throws {
        // Objects area (type 2) first, with its RDOT payload field — must be
        // ignored. Then a weather area (type 3) + RDWT with two entries.
        var objectsHeader = Data()
        objectsHeader.appendUInt32(2) // type: objects
        objectsHeader.append(contentsOf: [0x00, 5]) // flags, priority
        objectsHeader.appendUInt16(0)

        var weatherHeader = Data()
        weatherHeader.appendUInt32(3) // type: weather
        weatherHeader.append(contentsOf: [0x01, 9]) // override flag, priority
        weatherHeader.appendUInt16(0)

        var rdwt = Data()
        rdwt.appendUInt32(0x40)
        rdwt.appendUInt32(70)
        rdwt.appendUInt32(0x50)
        rdwt.appendUInt32(0x41)
        rdwt.appendUInt32(30)
        rdwt.appendUInt32(0)

        let fields = ESMFixture.field("EDID", ESMFixture.zstring("TestRegion"))
            + ESMFixture.field("WNAM", formID(0x3C))
            + ESMFixture.field("RCLR", Data([255, 128, 64, 0]))
            + ESMFixture.field("RDAT", objectsHeader)
            + ESMFixture.field("RDOT", Data(count: 52)) // objects payload, ignored
            + ESMFixture.field("RDAT", weatherHeader)
            + ESMFixture.field("RDWT", rdwt)
        let region = try Region(record: record(ESMFixture.record(
            "REGN", formID: 0x3B, data: fields
        )))

        #expect(region.formID == FormID(0x3B))
        #expect(region.editorID == "TestRegion")
        #expect(region.worldspace == FormID(0x3C))
        let color = try #require(region.mapColor)
        #expect(color == SIMD3<Float>(255, 128, 64) / 255)
        #expect(region.weatherPriority == 9)
        #expect(region.weatherOverride)
        #expect(region.weatherList == [
            Region.WeatherChance(weather: FormID(0x40), chance: 70, global: FormID(0x50)),
            Region.WeatherChance(weather: FormID(0x41), chance: 30, global: nil)
        ])
    }

    @Test func skipsWeatherEntriesWithBadSize() throws {
        var weatherHeader = Data()
        weatherHeader.appendUInt32(3)
        weatherHeader.append(contentsOf: [0x00, 1])
        weatherHeader.appendUInt16(0)
        // 20 bytes: not a multiple of 12 -> RDWT rejected.
        let fields = ESMFixture.field("RDAT", weatherHeader)
            + ESMFixture.field("RDWT", Data(count: 20))
        let region = try Region(record: record(ESMFixture.record("REGN", data: fields)))
        #expect(region.weatherList.isEmpty)
        #expect(region.weatherPriority == 1)
    }

    @Test func ignoresRDWTOutsideWeatherArea() throws {
        // RDWT under a sound (type 7) area must not bind.
        var soundHeader = Data()
        soundHeader.appendUInt32(7)
        soundHeader.append(contentsOf: [0x00, 2])
        soundHeader.appendUInt16(0)
        var rdwt = Data()
        rdwt.appendUInt32(0x40)
        rdwt.appendUInt32(100)
        rdwt.appendUInt32(0)
        let fields = ESMFixture.field("RDAT", soundHeader)
            + ESMFixture.field("RDWT", rdwt)
        let region = try Region(record: record(ESMFixture.record("REGN", data: fields)))
        #expect(region.weatherList.isEmpty)
        #expect(region.weatherPriority == nil)
    }

    @Test func missingFieldsDecodeToEmptyAndNil() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("Bare"))
        let region = try Region(record: record(ESMFixture.record("REGN", data: fields)))
        #expect(region.editorID == "Bare")
        #expect(region.worldspace == nil)
        #expect(region.mapColor == nil)
        #expect(region.weatherList.isEmpty)
        #expect(region.weatherPriority == nil)
        #expect(!region.weatherOverride)
    }

    @Test func wrongRecordTypeThrows() throws {
        #expect(throws: ESMError.self) {
            _ = try Region(record: record(ESMFixture.record("WTHR", data: Data())))
        }
    }

    private func formID(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return data
    }

    private func record(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }
}
