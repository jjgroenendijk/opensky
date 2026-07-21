// WTHR decoder coverage over synthetic field bytes only (never extracted game
// files, AGENTS.md "Legal & IP boundary"). Layout sources: UESP WTHR + xEdit
// dev-4.1.5 wbDefinitionsTES5.pas; see docs/formats/records.md.

import Foundation
@testable import opensky
import simd
import Testing

struct WeatherRecordTests {
    /// One NAM0 component = four RGB triples (sunrise/day/sunset/night), each
    /// written as an RGBX quad (trailing pad byte).
    private static func layer(_ colors: [UInt8]...) -> Data {
        var out = Data()
        for rgb in colors {
            out.append(contentsOf: [rgb[0], rgb[1], rgb[2], 0]) // RGBX pad
        }
        return out
    }

    /// NAM0 with `count` components; component 0 + 8 carry distinct colors, rest 0.
    private static func nam0(componentCount: Int) -> Data {
        var out = Data()
        for index in 0 ..< componentCount {
            switch index {
            case 0: // Sky-Upper
                out += layer([10, 20, 30], [40, 50, 60], [70, 80, 90], [100, 110, 120])
            case 8: // Horizon
                out += layer([11, 22, 33], [44, 55, 66], [77, 88, 99], [111, 122, 133])
            default:
                out += Data(count: 16)
            }
        }
        return out
    }

    private static func floats(_ values: [Float]) -> Data {
        var out = Data()
        for value in values {
            out.appendUInt32(value.bitPattern)
        }
        return out
    }

    /// 19-byte SSE DATA: rainy flag (0x04), wind speed 128, direction 128.
    private static func data19(flags: UInt8) -> Data {
        var out = Data()
        out.append(128) // wind speed -> 128/255
        out.append(contentsOf: [0, 0]) // unknown
        out.append(51) // trans delta -> 51/255 * 0.25
        out.append(200) // sun glare
        out.append(25) // sun damage
        out.append(60) // precip begin fade in
        out.append(70) // precip end fade out
        out.append(80) // thunder begin fade in
        out.append(90) // thunder end fade out
        out.append(15) // thunder frequency (raw)
        out.append(flags)
        out.append(contentsOf: [200, 100, 50]) // lightning RGB
        out.append(contentsOf: [0, 0]) // visual effect begin/end
        out.append(128) // wind direction -> 128/255 * 360
        out.append(64) // wind dir range -> 64/255 * 180
        return out
    }

    /// 32-byte DALC: seven RGBX colors (X+/X-/Y+/Y-/Z+/Z-/Specular), then a
    /// float Scale. Color `n` = (base+3n, base+3n+1, base+3n+2).
    private static func dalc(base: UInt8, scale: Float) -> Data {
        var out = Data()
        for index in 0 ..< 7 {
            let channel = base &+ UInt8(index &* 3)
            out.append(contentsOf: [channel, channel &+ 1, channel &+ 2, 0]) // RGBX pad
        }
        out.appendUInt32(scale.bitPattern)
        return out
    }

    @Test func decodesDirectionalAmbientKeyframes() throws {
        let fields = ESMFixture.field("DALC", Self.dalc(base: 10, scale: 1.5))
            + ESMFixture.field("DALC", Self.dalc(base: 40, scale: 2.5))
            + ESMFixture.field("DALC", Self.dalc(base: 70, scale: 3.5))
            + ESMFixture.field("DALC", Self.dalc(base: 100, scale: 4.5))
        let weather = try Self.decode("WTHR", fields: fields)
        let ambient = try #require(weather.directionalAmbient)
        // First DALC -> Sunrise; its X+ axis is color 0 = (base, base+1, base+2).
        #expect(ambient.sunrise.colors.positiveX == SIMD3<Float>(10, 11, 12) / 255)
        // Z- is color 5 = base + 15.
        #expect(ambient.sunrise.colors.negativeZ == SIMD3<Float>(25, 26, 27) / 255)
        // Specular is color 6 = base + 18.
        #expect(ambient.sunrise.specular == SIMD3<Float>(28, 29, 30) / 255)
        #expect(ambient.sunrise.scale == 1.5)
        // Second/third/fourth DALC -> Day/Sunset/Night.
        #expect(ambient.day.colors.positiveX == SIMD3<Float>(40, 41, 42) / 255)
        #expect(ambient.sunset.colors.positiveX == SIMD3<Float>(70, 71, 72) / 255)
        #expect(ambient.night.colors.positiveX == SIMD3<Float>(100, 101, 102) / 255)
        #expect(ambient.night.scale == 4.5)
    }

    @Test func skipsPartialDirectionalAmbient() throws {
        // Only three DALC -> no defined time-of-day mapping -> nil.
        let fields = ESMFixture.field("DALC", Self.dalc(base: 10, scale: 1))
            + ESMFixture.field("DALC", Self.dalc(base: 20, scale: 1))
            + ESMFixture.field("DALC", Self.dalc(base: 30, scale: 1))
        let weather = try Self.decode("WTHR", fields: fields)
        #expect(weather.directionalAmbient == nil)
    }

    @Test func skipsUndersizedDirectionalAmbient() throws {
        // A 16-byte DALC is not the 32-byte layout -> skipped, not guessed.
        let fields = ESMFixture.field("DALC", Data(count: 16))
            + ESMFixture.field("DALC", Self.dalc(base: 10, scale: 1))
            + ESMFixture.field("DALC", Self.dalc(base: 20, scale: 1))
            + ESMFixture.field("DALC", Self.dalc(base: 30, scale: 1))
            + ESMFixture.field("DALC", Self.dalc(base: 40, scale: 1))
        let weather = try Self.decode("WTHR", fields: fields)
        // Four valid frames remain after the undersized one is dropped.
        let ambient = try #require(weather.directionalAmbient)
        #expect(ambient.sunrise.colors.positiveX == SIMD3<Float>(10, 11, 12) / 255)
    }

    @Test func decodesFullWeather() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("TestWeather"))
            + ESMFixture.field("NAM0", Self.nam0(componentCount: 17))
            + ESMFixture.field(
                "FNAM", Self.floats([100, 2000, 50, 1500, 1.5, 2.5, 9000, 8000])
            )
            + ESMFixture.field("DATA", Self.data19(flags: 0x04))
        let weather = try Self.decode("WTHR", formID: 0x0A, fields: fields)

        #expect(weather.formID == FormID(0x0A))
        #expect(weather.editorID == "TestWeather")

        let colors = try #require(weather.colors)
        #expect(colors.count == 17)
        let sky = try #require(weather.skyUpper)
        #expect(sky.sunrise == SIMD3<Float>(10, 20, 30) / 255)
        #expect(sky.day == SIMD3<Float>(40, 50, 60) / 255)
        #expect(sky.sunset == SIMD3<Float>(70, 80, 90) / 255)
        #expect(sky.night == SIMD3<Float>(100, 110, 120) / 255)
        let horizon = try #require(weather.horizon)
        #expect(horizon.sunrise == SIMD3<Float>(11, 22, 33) / 255)
        #expect(horizon.night == SIMD3<Float>(111, 122, 133) / 255)
        #expect(weather.moonGlareIsPresent(colors))

        let fog = try #require(weather.fog)
        #expect(fog.dayNear == 100)
        #expect(fog.dayFar == 2000)
        #expect(fog.nightNear == 50)
        #expect(fog.nightFar == 1500)
        #expect(fog.dayPow == 1.5)
        #expect(fog.nightPow == 2.5)
        #expect(fog.dayMax == 9000)
        #expect(fog.nightMax == 8000)

        let data = try #require(weather.data)
        #expect(data.windSpeed == Float(128) / 255)
        #expect(data.transDelta == Float(51) / 255 * 0.25)
        #expect(data.thunderFrequency == 15)
        #expect(data.flags == 0x04)
        #expect(data.precipitation == .rainy)
        #expect(data.lightningColor == SIMD3<Float>(200, 100, 50) / 255)
        #expect(abs(data.windDirection - 128.0 / 255 * 360) < 0.001)
        #expect(abs(data.windDirectionRange - 64.0 / 255 * 180) < 0.001)
    }

    @Test func decodes16ComponentNAM0() throws {
        let fields = ESMFixture.field("NAM0", Self.nam0(componentCount: 16))
        let weather = try Self.decode("WTHR", fields: fields)
        let colors = try #require(weather.colors)
        #expect(colors.count == 16)
        #expect(weather.sunGlare != nil) // index 15 present
        #expect(weather.colors(for: .moonGlare) == nil) // index 16 absent
    }

    @Test func decodesLegacyShortFNAM() throws {
        let fields = ESMFixture.field("FNAM", Self.floats([100, 2000, 50, 1500]))
        let weather = try Self.decode("WTHR", fields: fields)
        let fog = try #require(weather.fog)
        #expect(fog.dayNear == 100)
        #expect(fog.nightFar == 1500)
        #expect(fog.dayPow == nil)
        #expect(fog.nightMax == nil)
    }

    @Test func mapsClassificationFlagsToPrecipitation() throws {
        let cases: [(UInt8, Weather.Precipitation)] = [
            (0x00, .none), (0x01, .pleasant), (0x02, .cloudy),
            (0x04, .rainy), (0x08, .snow)
        ]
        for (flags, expected) in cases {
            let fields = ESMFixture.field("DATA", Self.data19(flags: flags))
            let weather = try Self.decode("WTHR", fields: fields)
            let data = try #require(weather.data)
            #expect(data.precipitation == expected)
        }
    }

    @Test func skipsUnknownSizeDATAWithoutThrowing() throws {
        // 18-byte DATA is not the known SSE size -> left nil, no throw.
        let fields = ESMFixture.field("DATA", Data(count: 18))
        let weather = try Self.decode("WTHR", fields: fields)
        #expect(weather.data == nil)
    }

    @Test func skipsNAM0NotDivisibleBy16() throws {
        let fields = ESMFixture.field("NAM0", Data(count: 20))
        let weather = try Self.decode("WTHR", fields: fields)
        #expect(weather.colors == nil)
    }

    @Test func throwsOnWrongRecordType() throws {
        let bytes = ESMFixture.record(
            "WATR",
            data: ESMFixture.field("EDID", ESMFixture.zstring("X"))
        )
        let record = try Self.record(bytes)
        #expect(throws: ESMError.self) { try Weather(record: record) }
    }

    @Test func missingOptionalFieldsAreNil() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("Bare"))
        let weather = try Self.decode("WTHR", fields: fields)
        #expect(weather.editorID == "Bare")
        #expect(weather.colors == nil)
        #expect(weather.fog == nil)
        #expect(weather.data == nil)
        #expect(weather.directionalAmbient == nil)
    }

    private static func decode(_ type: String, formID: UInt32 = 0, fields: Data) throws -> Weather {
        try Weather(record: record(ESMFixture.record(type, formID: formID, data: fields)))
    }

    private static func record(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }
}

extension Weather {
    /// 17-component NAM0 exposes moon glare (index 16).
    fileprivate func moonGlareIsPresent(_: [Colors]) -> Bool {
        colors(for: .moonGlare) != nil
    }
}
