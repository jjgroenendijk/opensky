// A region named by `XEMI` lights its references with its weather's `Effect Lighting`
// colour, which follows the time of day.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyWeather
import simd
import Testing

@MainActor
struct RegionEmittanceTests {
    private static let glowRegion: UInt32 = 0x400
    private static let darkWeather: UInt32 = 0x100
    private static let glowWeather: UInt32 = 0x200

    @Test func theColourFollowsTheHour() throws {
        let system = try WeatherSystem(store: Self.store(), worldspaceFormID: nil)
        let noon = system.regionEmittance(for: [Self.glowRegion], hour: 12)
        let midnight = system.regionEmittance(for: [Self.glowRegion], hour: 0)
        #expect(noon[Self.glowRegion] == SIMD3(repeating: 0))
        let night = try #require(midnight[Self.glowRegion])
        #expect(simd_reduce_max(abs(night - SIMD3(1, 128 / 255, 0))) < 1e-5)
    }

    @Test func anUnknownRegionGivesNoColour() throws {
        let system = try WeatherSystem(store: Self.store(), worldspaceFormID: nil)
        #expect(system.regionEmittance(for: [0x999], hour: 0).isEmpty)
    }

    @Test func theActiveWeatherWinsWhenTheRegionListsIt() throws {
        let region = try #require(Self.store().region(FormID(Self.glowRegion)))
        let likely = WeatherSystem.emittanceWeather(of: region, active: nil)
        let active = WeatherSystem.emittanceWeather(of: region, active: FormID(Self.darkWeather))
        let unlisted = WeatherSystem.emittanceWeather(of: region, active: FormID(0x777))
        #expect(likely == FormID(Self.glowWeather))
        #expect(active == FormID(Self.darkWeather))
        #expect(unlisted == FormID(Self.glowWeather))
    }

    // MARK: - Fixtures

    private static func store() throws -> WeatherStore {
        let plugin = ESMFixture.tes4()
            + ESMFixture.topGroup(
                "WTHR",
                contents: weather(darkWeather, night: [0, 0, 0])
                    + weather(glowWeather, night: [0xFF, 0x80, 0])
            )
            + ESMFixture.topGroup("REGN", contents: region())
        return try WeatherStore(file: ESMFile(data: plugin))
    }

    /// NAM0 with only the `Effect Lighting` layer set: black by day, `night` at night.
    private static func weather(_ formID: UInt32, night: [UInt8]) -> Data {
        var nam0 = Data()
        for index in 0 ..< 17 {
            nam0.append(Data(count: 12))
            nam0.append(contentsOf: index == 9 ? night + [0] : [0, 0, 0, 0])
        }
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("WTHR\(formID)"))
            + ESMFixture.field("NAM0", nam0)
        return ESMFixture.record("WTHR", formID: formID, data: fields)
    }

    private static func region() -> Data {
        var rdwt = Data()
        for (weather, chance) in [(darkWeather, 20), (glowWeather, 80)] as [(UInt32, UInt32)] {
            rdwt.appendUInt32(weather)
            rdwt.appendUInt32(chance)
            rdwt.appendUInt32(0)
        }
        var rdat = Data()
        rdat.appendUInt32(3) // weather area
        rdat.append(contentsOf: [0, 0, 0, 0]) // flags, priority, padding
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("FXLightRegionTest"))
            + ESMFixture.field("RDAT", rdat)
            + ESMFixture.field("RDWT", rdwt)
        return ESMFixture.record("REGN", formID: glowRegion, data: fields)
    }
}
