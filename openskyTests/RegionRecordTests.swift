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

    @Test func decodesSoundAreaEntries() throws {
        // Sound area (type 7) with two RDSA entries. Fields per xEdit
        // wbDefinitionsCommon.pas:8729-8747: formid, uint32 conditions, float chance.
        var soundHeader = Data()
        soundHeader.appendUInt32(7)
        soundHeader.append(contentsOf: [0x01, 4]) // override flag, priority
        soundHeader.appendUInt16(0)

        var entry1 = Data()
        entry1.appendUInt32(0x100) // sound SNDR
        entry1.appendUInt32(0x01 | 0x04) // pleasant | rainy
        entry1.appendUInt32(Float(0.5).bitPattern)

        var entry2 = Data()
        entry2.appendUInt32(0x101)
        entry2.appendUInt32(0) // all weather (empty set)
        entry2.appendUInt32(Float(1.0).bitPattern)

        let fields = ESMFixture.field("EDID", ESMFixture.zstring("SoundRegion"))
            + ESMFixture.field("RDAT", soundHeader)
            + ESMFixture.field("RDSA", entry1 + entry2)
        let region = try Region(record: record(ESMFixture.record(
            "REGN", formID: 0x42, data: fields
        )))

        #expect(region.soundPriority == 4)
        #expect(region.soundOverride)
        #expect(region.soundList.count == 2)
        let first = try #require(region.soundList.first)
        #expect(first.sound == FormID(0x100))
        #expect(first.conditions == [.pleasant, .rainy])
        #expect(first.chance == 0.5)
        let second = try #require(region.soundList.last)
        #expect(second.sound == FormID(0x101))
        #expect(second.conditions.isEmpty)
        #expect(second.chance == 1.0)
    }

    @Test func skipsSoundEntriesWithBadSize() throws {
        var soundHeader = Data()
        soundHeader.appendUInt32(7)
        soundHeader.append(contentsOf: [0x00, 1])
        soundHeader.appendUInt16(0)
        // 13 bytes: not a multiple of 12 -> RDSA rejected.
        let fields = ESMFixture.field("RDAT", soundHeader)
            + ESMFixture.field("RDSA", Data(count: 13))
        let region = try Region(record: record(ESMFixture.record("REGN", data: fields)))
        #expect(region.soundList.isEmpty)
        #expect(region.soundPriority == 1)
    }

    @Test func ignoresRDSAOutsideSoundArea() throws {
        // RDSA under a weather area must not bind.
        var weatherHeader = Data()
        weatherHeader.appendUInt32(3)
        weatherHeader.append(contentsOf: [0x00, 1])
        weatherHeader.appendUInt16(0)
        let fields = ESMFixture.field("RDAT", weatherHeader)
            + ESMFixture.field("RDSA", Data(count: 12))
        let region = try Region(record: record(ESMFixture.record("REGN", data: fields)))
        #expect(region.soundList.isEmpty)
        #expect(region.soundPriority == nil)
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
        #expect(region.soundList.isEmpty)
        #expect(region.soundPriority == nil)
        #expect(!region.soundOverride)
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
