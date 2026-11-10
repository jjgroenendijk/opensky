// The sun path, the light, the moon phases and fades, the star turn, and the aurora
// fade, over synthetic CLMT and WTHR records.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyRenderCore
import simd
import Testing

struct CelestialSkyTests {
    private typealias Fixture = ESMFixture

    // MARK: - Sun

    /// The fixture's horizon hours are 7 and 19 with a half-hour fade, so the disc's day
    /// runs from 6.75 to 19.25 and peaks at 13.
    @Test func theSunRunsATriangleFromEastToWest() throws {
        let climate = try Self.climate()
        let rise = sky(hour: 6.75, climate: climate).sunDirection
        let noon = sky(hour: 13, climate: climate).sunDirection
        let set = sky(hour: 19.25, climate: climate).sunDirection
        #expect(rise.x > 0.99 && abs(rise.z) < 1e-4)
        #expect(noon.z > 0.99 && noon.y > 0)
        #expect(set.x < -0.99 && abs(set.z) < 1e-4)
        // Halfway up the morning the height equals the east reach: a straight edge.
        let morning = sky(hour: 9.875, climate: climate).sunDirection
        #expect(abs(morning.x - morning.z) < 1e-4)
        // By night it runs back east, overhead in the middle of the night, unseen.
        let midnight = sky(hour: 1, climate: climate)
        #expect(midnight.sunDirection.z > 0.99 && midnight.sunAlpha == 0)
    }

    @Test func theSunDiscFadesAcrossTheHorizonHours() throws {
        let climate = try Self.climate()
        #expect(sky(hour: 1, climate: climate).sunAlpha == 0)
        #expect(sky(hour: 13, climate: climate).sunAlpha == 1)
        #expect(abs(sky(hour: 7, climate: climate).sunAlpha - 0.5) < 1e-4)
        #expect(abs(sky(hour: 19, climate: climate).sunAlpha - 0.5) < 1e-4)
    }

    @Test func theLightComesFromAFixedHeightAndHasNoJumpAtSunset() throws {
        let climate = try Self.climate()
        // fSunDirXExtreme 200 over fSunXExtreme 400 halves the east part; the height is
        // -fSunZExtreme, 150, so the light is never lower than about 37 degrees.
        let noon = sky(hour: 13, climate: climate).lightDirection
        #expect(simd_distance(noon, simd_normalize(SIMD3(0, -20, -150))) < 1e-4)
        for hour in stride(from: Float(0), to: 24, by: 0.25) {
            let light = sky(hour: hour, climate: climate).lightDirection
            #expect(-light.z > sin(36 * Float.pi / 180), "light too low at \(hour)")
        }
        let before = sky(hour: 19.24, climate: climate).lightDirection
        let after = sky(hour: 19.26, climate: climate).lightDirection
        #expect(simd_distance(before, after) < 0.01)
    }

    @Test func glareTakesTheWeatherValueAboveTheMinimum() throws {
        let climate = try Self.climate()
        let bright = try Self.weather(sunGlare: 0xFF)
        let dull = try Self.weather(sunGlare: 0)
        #expect(sky(hour: 13, climate: climate, weathers: [(bright, 1)]).glareScale == 1)
        #expect(sky(hour: 13, climate: climate, weathers: [(dull, 1)]).glareScale == 0.25)
    }

    // MARK: - Moons

    @Test func moonPhasesStepByThePhaseLength() {
        #expect(MoonPhase.at(daysPassed: 0, phaseLengthDays: 3) == .full)
        #expect(MoonPhase.at(daysPassed: 3.5, phaseLengthDays: 3) == .threeWaning)
        #expect(MoonPhase.at(daysPassed: 12, phaseLengthDays: 3) == .new)
        #expect(MoonPhase.at(daysPassed: 24, phaseLengthDays: 3) == .full)
        #expect(MoonPhase.at(daysPassed: -1, phaseLengthDays: 3) == .threeWaxing)
        #expect(MoonPhase.at(daysPassed: 40, phaseLengthDays: 0) == .full)
    }

    @Test func aMoonInViewKeepsItsPhaseUntilItIsHidden() throws {
        let climate = try Self.climate(moons: 0xC3)
        // Day 6 starts the half waning phase, but Masser stands at the top of its path:
        // it rose past its fade end at day 5.81, still three waning.
        let masser = try #require(sky(hour: 0, climate: climate, days: 6).moons.first)
        #expect(masser.alpha == 1)
        #expect(masser.phase == .threeWaning)
        let hidden = try #require(sky(hour: 0, climate: climate, days: 6.5).moons.first)
        #expect(hidden.alpha == 0)
        #expect(hidden.phase == .halfWaning)
    }

    @Test func theClimateNamesWhichMoonsShowAndTheirTextures() throws {
        let both = try sky(hour: 1, climate: Self.climate(moons: 0xC3), days: 6.5)
        #expect(both.moons.map(\.moon) == [.masser, .secunda])
        #expect(both.moons.map(\.texture) == [
            "sky\\masser_half_wan.dds",
            "sky\\secunda_half_wan.dds"
        ])
        // iMasserSize 90 over the 400-unit sun reach.
        #expect(abs(both.moons[0].halfSize - 45.0 / 400) < 1e-6)
        let secundaOnly = try sky(hour: 1, climate: Self.climate(moons: 0x83))
        #expect(secundaOnly.moons.map(\.moon) == [.secunda])
    }

    @Test func aMoonFadesByItsHeightAlongItsTiltedPath() {
        let tuning = SkySettings.vanilla.masser
        func fade(pathHeight degrees: Float) -> Float {
            CelestialSky.moonFade(pathAngle: degrees * .pi / 180, tuning: tuning)
        }
        #expect(fade(pathHeight: 10) == 0)
        #expect(fade(pathHeight: 20) == 0)
        #expect(abs(fade(pathHeight: 27.5) - 0.5) < 1e-4)
        #expect(fade(pathHeight: 35) == 1)
        #expect(fade(pathHeight: 145) == 1)
        #expect(fade(pathHeight: -30) == 0)
        // The game showed Masser at alpha 0.674 at 24.3 degrees of elevation.
        let direction = CelestialSky.moonDirection(pathAngle: 30.2 * .pi / 180, tuning: tuning)
        #expect(abs(asin(direction.z) * 180 / .pi - 24.3) < 0.1)
        #expect(abs(fade(pathHeight: 30.2) - 0.68) < 0.01)
    }

    @Test func theMoonsFollowThePathsMeasuredInTheGame() {
        let settings = SkySettings.vanilla
        func degrees(_ moon: MoonSettings, days: Float) -> (elevation: Float, azimuth: Float) {
            let angle = CelestialSky.moonPathAngle(daysPassed: days, tuning: moon)
            let direction = CelestialSky.moonDirection(pathAngle: angle, tuning: moon)
            let azimuth = atan2(direction.x, direction.y) * 180 / .pi
            return (asin(direction.z) * 180 / .pi, azimuth < 0 ? azimuth + 360 : azimuth)
        }
        // Reference game, day 25: Masser highest in the east at midnight, rising at 18:00.
        let midnight = degrees(settings.masser, days: 25)
        #expect(abs(midnight.elevation - 55) < 0.2 && abs(midnight.azimuth - 90) < 0.2)
        let rising = degrees(settings.masser, days: 25 + 18 / 24)
        #expect(abs(rising.elevation) < 0.2 && abs(rising.azimuth - 35) < 0.2)
        // Day 26 at midnight: Secunda at 11.4 degrees, azimuth 128.6.
        let secunda = degrees(settings.secunda, days: 26)
        #expect(abs(secunda.elevation - 11.4) < 0.2 && abs(secunda.azimuth - 128.6) < 0.2)
    }

    // MARK: - Stars and aurora

    @Test func theStarsTurnOnceInStarsRotateDays() throws {
        let climate = try Self.climate()
        let quarter = sky(hour: 0, climate: climate, days: SkySettings.vanilla.starsRotateDays / 4)
        #expect(abs(quarter.starsAngle + .pi / 2) < 1e-3)
        #expect(abs(simd_length(quarter.starsAxis) - 1) < 1e-5)
        #expect(quarter.starsAxis.y > 0)
        #expect(quarter.nightSkyModel == "Sky\\Stars.nif")
    }

    @Test func theAuroraFadesInTheEveningAndOutInTheMorning() {
        let settings = SkySettings.vanilla
        let fade = { (hour: Float) in CelestialSky.auroraFade(hour: hour, settings: settings) }
        #expect(fade(12) == 0)
        #expect(fade(19) == 0)
        #expect(abs(fade(19.5) - 0.5) < 1e-4)
        #expect(fade(20) == 1)
        #expect(fade(0) == 1)
        #expect(abs(fade(5.5) - 0.5) < 1e-4)
        #expect(fade(6) == 0)
    }

    @Test func aWeatherAuroraShowsByItsWeightAndAlwaysVisibleKeepsItByDay() throws {
        let climate = try Self.climate()
        let night = try Self.weather(aurora: "Sky\\Aurora.nif")
        let always = try Self.weather(flags: 0x10, aurora: "Sky\\Aurora.nif")
        let blend = sky(hour: 0, climate: climate, weathers: [(night, 0.25), (night, 0.25)])
        #expect(blend.auroras == [AuroraState(model: "Sky\\Aurora.nif", alpha: 0.5)])
        #expect(sky(hour: 12, climate: climate, weathers: [(night, 1)]).auroras.isEmpty)
        #expect(sky(hour: 12, climate: climate, weathers: [(always, 1)]).auroras.count == 1)
    }

    @Test func anAuroraThatFollowsTheSunTurnsToItsBearing() throws {
        let climate = try Self.climate()
        let follows = try Self.weather(flags: 0x30, aurora: "Sky\\Aurora.nif")
        let still = try Self.weather(flags: 0x10, aurora: "Sky\\Aurora.nif")
        // At sunrise the sun is due east and a little north.
        let morning = sky(hour: 7, climate: climate, weathers: [(follows, 1)])
        let east = try #require(morning.auroras.first)
        #expect(abs(east.yaw - atan2(morning.sunDirection.y, morning.sunDirection.x)) < 1e-5)
        #expect(east.yaw > 0 && east.yaw < 0.2)
        #expect(sky(hour: 7, climate: climate, weathers: [(still, 1)]).auroras.first?.yaw == 0)
    }

    // MARK: - Fixtures

    private func sky(
        hour: Float, climate: Climate, days: Float = 0,
        weathers: [(Weather, Float)] = [], settings: SkySettings = .vanilla
    ) -> CelestialSky {
        CelestialSky.resolve(
            at: (hour, days), climate: climate,
            weathers: weathers.map { (weather: $0.0, weight: $0.1) }, settings: settings
        )
    }

    /// Sunrise 06:00-08:00 and sunset 18:00-20:00: the sun is on the horizon at 07:00 and 19:00.
    private static func climate(moons: UInt8 = 0xC3) throws -> Climate {
        let fields = Fixture.field("EDID", Fixture.zstring("TestClimate"))
            + Fixture.field("FNAM", Fixture.zstring("Sky\\Sun.dds"))
            + Fixture.field("GNAM", Fixture.zstring("Sky\\SunGlare.dds"))
            + Fixture.field("MODL", Fixture.zstring("Sky\\Stars.nif"))
            + Fixture.field("TNAM", Data([36, 48, 108, 120, 50, moons]))
        return try Climate(record: Fixture.parseRecord(
            Fixture.record("CLMT", formID: 0x30, data: fields)
        ))
    }

    private static func weather(
        sunGlare: UInt8 = 0, flags: UInt8 = 0, aurora: String? = nil
    ) throws -> Weather {
        let data = Data([0, 0, 0, 0, sunGlare, 0, 0, 0, 0, 0, 15, flags, 0, 0, 0, 0, 0, 0, 0])
        var fields = Fixture.field("EDID", Fixture.zstring("TestWeather"))
            + Fixture.field("DATA", data)
        if let aurora {
            fields += Fixture.field("MODL", Fixture.zstring(aurora))
        }
        return try Weather(record: Fixture.parseRecord(
            Fixture.record("WTHR", formID: 0x40, data: fields)
        ))
    }
}
