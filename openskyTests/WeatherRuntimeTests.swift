// Weather runtime coverage over synthetic fixtures only (never extracted game
// files, AGENTS.md "Legal & IP boundary"): time-of-day keyframe blend, resolved
// weather blend math, wind blending, region/climate selection semantics, the
// deterministic weighted pick, and the WeatherSystem transition machine.

import Foundation
@testable import opensky
import simd
import Testing

struct WeatherRuntimeTests {
    // MARK: - Time-of-day weights

    @Test func timeOfDayWeightsPeakPerPhase() {
        // Default windows: sunrise 05-07 (mid 06), sunset 17-19 (mid 18).
        #expect(TimeOfDayWeights(hour: 0, timing: nil).night == 1)
        #expect(TimeOfDayWeights(hour: 12, timing: nil).day == 1)
        #expect(TimeOfDayWeights(hour: 6, timing: nil).sunrise == 1)
        #expect(TimeOfDayWeights(hour: 18, timing: nil).sunset == 1)
    }

    @Test func timeOfDayWeightsSumToOneAndWrap() {
        for hour in stride(from: -6 as Float, through: 30, by: 0.37) {
            let weights = TimeOfDayWeights(hour: hour, timing: nil)
            let sum = weights.sunrise + weights.day + weights.sunset + weights.night
            #expect(abs(sum - 1) < 1e-4, "weights at \(hour) summed to \(sum)")
        }
        // Midnight wrap: 24:00 resolves like 00:00.
        #expect(TimeOfDayWeights(hour: 24, timing: nil) == TimeOfDayWeights(hour: 0, timing: nil))
    }

    @Test func timeOfDayWeightsBlendChannels() {
        let noon = TimeOfDayWeights(hour: 12, timing: nil)
        // Full day -> picks the day value verbatim.
        #expect(noon.blend(1, 2, 3, 4) == 2)
        #expect(noon.blend(SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1), SIMD3(1, 1, 1))
            == SIMD3(0, 1, 0))
    }

    // MARK: - Wind

    @Test func windFromDataAndBlend() {
        let east = WindState(direction: SIMD2(1, 0), speed: 1, meanderRange: 20)
        let north = WindState(direction: SIMD2(0, 1), speed: 1, meanderRange: 40)
        let mid = WindState.blend(east, north, 0.5)
        #expect(abs(mid.meanderRange - 30) < 1e-4)
        // Halfway between +X and +Y points into the first quadrant.
        #expect(mid.direction.x > 0 && mid.direction.y > 0)
        #expect(WindState.blend(east, north, 0) == east)
        #expect(WindState.blend(east, north, 1).direction.y > 0.99)
    }

    // MARK: - Resolved blend

    @Test func resolvedBlendEndpointsAndMonotonic() throws {
        let low = try Self.store().weather(FormID(0x100))
        let high = try Self.store().weather(FormID(0x200))
        let a = try ResolvedWeather.resolve(#require(low), hour: 12, timing: nil)
        let b = try ResolvedWeather.resolve(#require(high), hour: 12, timing: nil)
        // Endpoints land on each source's sky palette exactly (mix at 0/1).
        #expect(ResolvedWeather.blend(a, b, 0).skyUpper == a.skyUpper)
        #expect(ResolvedWeather.blend(a, b, 1).skyUpper == b.skyUpper)
        // skyUpper.day differs (0x40 vs 0x80); blend is monotone across t.
        var previous = ResolvedWeather.blend(a, b, 0).skyUpper.x
        for step in 1 ... 10 {
            let value = ResolvedWeather.blend(a, b, Float(step) / 10).skyUpper.x
            #expect(value >= previous - 1e-6)
            previous = value
        }
    }

    @Test func resolvedFogBlendsDayNight() throws {
        let weather = try #require(Self.store().weather(FormID(0x100)))
        let day = ResolvedWeather.resolve(weather, hour: 12, timing: nil)
        let night = ResolvedWeather.resolve(weather, hour: 0, timing: nil)
        #expect(day.fogEnabled)
        // FNAM day near 100 / night near 400 -> day resolves nearer.
        #expect(day.fogNearDistance < night.fogNearDistance)
        #expect(abs(day.fogNearDistance - 100) < 1e-3)
        #expect(abs(night.fogNearDistance - 400) < 1e-3)
    }

    // MARK: - Selection

    @Test func climateFallbackWhenNoRegions() throws {
        let store = try Self.store()
        let pool = WeatherSelection.candidates(worldspace: 0x500, regionIDs: [], store: store)
        #expect(pool.map(\.weather) == [FormID(0x100), FormID(0x200)])
    }

    @Test func regionOverrideReplacesClimate() throws {
        let store = try Self.store()
        // Region 0x400 (priority 5, override on) lists only weather B.
        let pool = WeatherSelection.candidates(
            worldspace: 0x500, regionIDs: [FormID(0x400)], store: store
        )
        #expect(pool.map(\.weather) == [FormID(0x200)])
    }

    @Test func regionWithoutOverrideAppendsClimate() throws {
        let store = try Self.store()
        // Region 0x401 (priority 3, override off) lists weather A, then climate.
        let pool = WeatherSelection.candidates(
            worldspace: 0x500, regionIDs: [FormID(0x401)], store: store
        )
        #expect(pool.first?.weather == FormID(0x100))
        #expect(pool.count == 3) // region A + climate A,B
    }

    @Test func highestPriorityRegionWins() throws {
        let store = try Self.store()
        // Both regions apply; 0x400 (priority 5, override) beats 0x401 (3).
        let pool = WeatherSelection.candidates(
            worldspace: 0x500, regionIDs: [FormID(0x401), FormID(0x400)], store: store
        )
        #expect(pool.map(\.weather) == [FormID(0x200)])
    }

    // MARK: - Weighted pick

    @Test func pickIsDeterministicPerSeed() {
        let pool = [
            WeightedWeather(weather: FormID(0x100), chance: 70),
            WeightedWeather(weather: FormID(0x200), chance: 30)
        ]
        for seed in UInt64(0) ..< 20 {
            #expect(WeatherSelection.pick(from: pool, seed: seed)
                == WeatherSelection.pick(from: pool, seed: seed))
        }
    }

    @Test func pickHonorsWeights() {
        let pool = [
            WeightedWeather(weather: FormID(0x100), chance: 70),
            WeightedWeather(weather: FormID(0x200), chance: 30)
        ]
        var counts: [FormID: Int] = [:]
        for seed in UInt64(0) ..< 4000 {
            if let pick = WeatherSelection.pick(from: pool, seed: seed) {
                counts[pick, default: 0] += 1
            }
        }
        let a = counts[FormID(0x100)] ?? 0
        let b = counts[FormID(0x200)] ?? 0
        #expect(a > b, "70-chance weather should win more often (\(a) vs \(b))")
        #expect(b > 0, "30-chance weather should still appear")
    }

    @Test func pickFallsBackToUniformWhenAllZero() {
        let pool = [
            WeightedWeather(weather: FormID(0x100), chance: 0),
            WeightedWeather(weather: FormID(0x200), chance: 0)
        ]
        #expect(WeatherSelection.pick(from: pool, seed: 7) != nil)
        #expect(WeatherSelection.pick(from: [], seed: 7) == nil)
    }

    @Test func precipitationPresetsPreferStableIDsThenClassification() throws {
        let store = try Self.presetStore()
        #expect(store.weather(for: .clear)?.editorID == "SkyrimClear")
        #expect(store.weather(for: .rain)?.editorID == "AlternateRain")
        #expect(store.weather(for: .snow)?.editorID == "SkyrimStormSnow")
    }

    // MARK: - WeatherSystem transitions

    @Test func forceInstantSnaps() throws {
        let system = try WeatherSystem(store: Self.store(), worldspaceFormID: 0x500)
        system.forceWeather(FormID(0x200), transition: .instant)
        system.update(deltaTime: 0, hour: 12)
        #expect(system.currentWeatherID == FormID(0x200))
        #expect(system.transitionFraction == 1)
    }

    @Test func forceTimedBlendsFromCurrentToTarget() throws {
        let system = try WeatherSystem(store: Self.store(), worldspaceFormID: 0x500)
        system.forceWeather(FormID(0x100), transition: .instant)
        system.update(deltaTime: 0, hour: 12)
        let windA = system.currentWind

        // B has a higher wind speed (0xFF vs 0x40); transition A -> B over time.
        system.forceWeather(FormID(0x200), transition: .timed)
        system.update(deltaTime: 0, hour: 12)
        #expect(system.transitionFraction == 0)
        #expect(abs(system.currentWind.speed - windA.speed) < 1e-4, "t=0 wind is still A")

        // Advance well past the derived duration -> fully settled on B.
        system.update(deltaTime: 100, hour: 12)
        #expect(system.transitionFraction == 1)
        #expect(system.currentWeatherID == FormID(0x200))
        #expect(system.currentWind.speed > windA.speed)
    }

    @Test func pausedTransitionFreezesBlendUntilResumed() throws {
        let system = try WeatherSystem(store: Self.store(), worldspaceFormID: 0x500)
        system.forceWeather(FormID(0x100), transition: .instant)
        system.update(deltaTime: 0, hour: 12)
        system.forceWeather(FormID(0x200), transition: .timed)
        system.update(deltaTime: 0.5, hour: 12)
        let pausedFraction = system.transitionFraction
        #expect(pausedFraction > 0 && pausedFraction < 1)

        system.transitionsPaused = true
        system.update(deltaTime: 100, hour: 12)
        #expect(system.transitionFraction == pausedFraction)

        system.transitionsPaused = false
        system.update(deltaTime: 100, hour: 12)
        #expect(system.transitionFraction == 1)
    }

    @Test func autoRerollAdvancesWithGameHours() throws {
        let system = try WeatherSystem(store: Self.store(), worldspaceFormID: 0x500)
        // Prime the time-of-day accumulator, then jump forward more than the
        // reroll interval; a target weather is still selected (never nil here).
        system.update(deltaTime: 0.016, hour: 8)
        system.update(deltaTime: 0.016, hour: 20)
        #expect(system.currentWeatherID != nil)
        #expect(system.resolvedWeather != nil)
    }

    @Test func inactiveWorldspaceResolvesNil() throws {
        // Worldspace with no climate + no regions -> no candidates -> nil.
        let system = try WeatherSystem(store: Self.store(), worldspaceFormID: 0x999)
        system.update(deltaTime: 0, hour: 12)
        #expect(system.resolvedWeather == nil)
        #expect(system.currentWind == .calm)
    }
}

/// Synthetic weather plugin fixtures, in an extension so they stay off the test
/// struct's body-length budget.
extension WeatherRuntimeTests {
    fileprivate static func store() throws -> WeatherStore {
        try WeatherStore(file: ESMFile(data: plugin()))
    }

    private static func presetStore() throws -> WeatherStore {
        let records = weather(
            formID: 0x600,
            skyUpperDay: 0x40,
            windSpeed: 0,
            transDelta: 0x33,
            editorID: "SkyrimClear",
            precipitationFlag: 0x01
        ) + weather(
            formID: 0x601,
            skyUpperDay: 0x40,
            windSpeed: 0,
            transDelta: 0x33,
            editorID: "AlternateRain",
            precipitationFlag: 0x04
        ) + weather(
            formID: 0x602,
            skyUpperDay: 0x40,
            windSpeed: 0,
            transDelta: 0x33,
            editorID: "SkyrimStormSnow",
            precipitationFlag: 0x08
        )
        let plugin = ESMFixture.tes4() + ESMFixture.topGroup("WTHR", contents: records)
        return try WeatherStore(file: ESMFile(data: plugin))
    }

    /// Plugin with two weathers, one climate, two regions, one worldspace.
    private static func plugin() -> Data {
        let weathers = ESMFixture.topGroup(
            "WTHR",
            contents: weather(
                formID: 0x100,
                skyUpperDay: 0x40,
                windSpeed: 0x40,
                transDelta: 0x33
            )
                + weather(
                    formID: 0x200,
                    skyUpperDay: 0x80,
                    windSpeed: 0xFF,
                    transDelta: 0xFF
                )
        )
        let climates = ESMFixture.topGroup(
            "CLMT",
            contents: climate(
                formID: 0x300,
                list: [(0x100, 70), (0x200, 30)]
            )
        )
        let regions = ESMFixture.topGroup(
            "REGN",
            contents: region(
                formID: 0x400,
                world: 0x500,
                priority: 5,
                override: true,
                list: [(0x200, 100)]
            )
                + region(
                    formID: 0x401,
                    world: 0x500,
                    priority: 3,
                    override: false,
                    list: [(0x100, 100)]
                )
        )
        let worlds = ESMFixture.topGroup(
            "WRLD",
            contents: worldspace(formID: 0x500, climate: 0x300)
        )
        return ESMFixture.tes4() + weathers + climates + regions + worlds
    }

    private static func weather(
        formID: UInt32,
        skyUpperDay: UInt8,
        windSpeed: UInt8,
        transDelta: UInt8,
        editorID: String? = nil,
        precipitationFlag: UInt8 = 0
    ) -> Data {
        // NAM0: 17 components; component 0 (sky-upper) day = grey skyUpperDay.
        var nam0 = Data()
        for index in 0 ..< 17 {
            if index == 0 {
                nam0.append(contentsOf: [0, 0, 0, 0]) // sunrise
                nam0.append(contentsOf: [skyUpperDay, skyUpperDay, skyUpperDay, 0]) // day
                nam0.append(contentsOf: [0, 0, 0, 0]) // sunset
                nam0.append(contentsOf: [0, 0, 0, 0]) // night
            } else {
                nam0.append(Data(count: 16))
            }
        }
        var fnam = Data()
        for value: Float in [100, 2000, 400, 3000, 1, 1, 1, 1] {
            fnam.appendFloat32(value)
        }
        var data = Data([windSpeed, 0, 0, transDelta, 0, 0, 0, 0, 0, 0, 15, 0, 0, 0, 0, 0, 0])
        data[11] = precipitationFlag
        data.append(64) // wind direction
        data.append(32) // wind direction range
        let fields = ESMFixture.field(
            "EDID", ESMFixture.zstring(editorID ?? "WTHR\(formID)")
        )
            + ESMFixture.field("NAM0", nam0)
            + ESMFixture.field("FNAM", fnam)
            + ESMFixture.field("DATA", data)
        return ESMFixture.record("WTHR", formID: formID, data: fields)
    }

    private static func climate(formID: UInt32, list: [(UInt32, UInt32)]) -> Data {
        var wlst = Data()
        for (weather, chance) in list {
            wlst.appendUInt32(weather)
            wlst.appendUInt32(chance)
            wlst.appendUInt32(0) // global
        }
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("CLMT\(formID)"))
            + ESMFixture.field("WLST", wlst)
        return ESMFixture.record("CLMT", formID: formID, data: fields)
    }

    private static func region(
        formID: UInt32, world: UInt32, priority: UInt8, override: Bool, list: [(UInt32, UInt32)]
    ) -> Data {
        var wnam = Data()
        wnam.appendUInt32(world)
        var rdat = Data()
        rdat.appendUInt32(3) // weather area type
        rdat.append(override ? 0x01 : 0x00) // flags
        rdat.append(priority)
        rdat.appendUInt16(0)
        var rdwt = Data()
        for (weather, chance) in list {
            rdwt.appendUInt32(weather)
            rdwt.appendUInt32(chance)
            rdwt.appendUInt32(0) // global
        }
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("REGN\(formID)"))
            + ESMFixture.field("WNAM", wnam)
            + ESMFixture.field("RDAT", rdat)
            + ESMFixture.field("RDWT", rdwt)
        return ESMFixture.record("REGN", formID: formID, data: fields)
    }

    private static func worldspace(formID: UInt32, climate: UInt32) -> Data {
        var cnam = Data()
        cnam.appendUInt32(climate)
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("TestWorld"))
            + ESMFixture.field("CNAM", cnam)
        return ESMFixture.record("WRLD", formID: formID, data: fields)
    }
}
