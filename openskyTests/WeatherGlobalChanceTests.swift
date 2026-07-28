// The first consumer of the runtime globals layer (issue #165): a CLMT WLST
// entry's global replaces its static weather chance, so mutating the global
// shifts which weather the deterministic pick returns. Synthetic fixtures only.
// Semantics + citation: docs/formats/weather.md.

import Foundation
@testable import opensky
import Testing

@MainActor
struct WeatherGlobalChanceTests {
    /// Object IDs of the two chance globals in the fixture plugin.
    private static let rainChanceKey = GlobalFixture.key(0x0800)
    private static let rainChanceID = FormID(0x0100_0800)

    @Test func climateChancesUseAuthoredValuesWithoutAResolver() throws {
        let candidates = try WeatherSelection.climateCandidates(
            worldspace: 0x500, store: Self.weatherStore()
        )
        #expect(candidates == [
            WeightedWeather(weather: FormID(0x100), chance: 90),
            WeightedWeather(weather: FormID(0x200), chance: 10)
        ])
    }

    @Test func unresolvableGlobalLeavesTheAuthoredChance() throws {
        // Resolver over a store with no GLOB records at all.
        let candidates = try WeatherSelection.climateCandidates(
            worldspace: 0x500,
            store: Self.weatherStore(),
            globals: GlobalResolution(defaults: GlobalStore.empty)
        )
        #expect(candidates.map(\.chance) == [90, 10])
    }

    @Test func pluginDefaultGlobalReplacesTheStaticChance() throws {
        let world = WorldStateStore()
        let candidates = try WeatherSelection.climateCandidates(
            worldspace: 0x500,
            store: Self.weatherStore(),
            globals: world.globalResolution(defaults: Self.globalStore())
        )
        // The rain entry's authored chance is 10, its global's default is 25.
        #expect(candidates == [
            WeightedWeather(weather: FormID(0x100), chance: 90),
            WeightedWeather(weather: FormID(0x200), chance: 25)
        ])
    }

    @Test func mutatedGlobalShiftsTheChance() throws {
        let defaults = try Self.globalStore()
        let world = WorldStateStore()
        world.setGlobal(400, formID: Self.rainChanceID, defaults: defaults)
        let candidates = try WeatherSelection.climateCandidates(
            worldspace: 0x500,
            store: Self.weatherStore(),
            globals: world.globalResolution(defaults: defaults)
        )
        #expect(candidates.map(\.chance) == [90, 400])

        // Resetting restores the plugin default, not the authored chance.
        world.resetGlobal(for: Self.rainChanceKey)
        let restored = try WeatherSelection.climateCandidates(
            worldspace: 0x500,
            store: Self.weatherStore(),
            globals: world.globalResolution(defaults: defaults)
        )
        #expect(restored.map(\.chance) == [90, 25])
    }

    /// A negative global cannot make a candidate consume weight; the weighted
    /// pick sums these.
    @Test func negativeGlobalClampsToZero() throws {
        let defaults = try Self.globalStore()
        let world = WorldStateStore()
        world.setGlobal(-50, formID: Self.rainChanceID, defaults: defaults)
        let candidates = try WeatherSelection.climateCandidates(
            worldspace: 0x500,
            store: Self.weatherStore(),
            globals: world.globalResolution(defaults: defaults)
        )
        #expect(candidates.map(\.chance) == [90, 0])
    }

    /// The observable end: the same seed picks a different weather once the
    /// global has moved the weight.
    @Test func mutatedGlobalChangesTheDeterministicPick() throws {
        let defaults = try Self.globalStore()
        let world = WorldStateStore()
        let store = try Self.weatherStore()
        let before = WeatherSelection.candidates(
            worldspace: 0x500,
            regionIDs: [],
            store: store,
            globals: world.globalResolution(defaults: defaults)
        )
        // Rain weight 25 against clear 90: this seed lands on clear.
        #expect(WeatherSelection.pick(from: before, seed: 7) == FormID(0x100))

        world.setGlobal(100_000, formID: Self.rainChanceID, defaults: defaults)
        let after = WeatherSelection.candidates(
            worldspace: 0x500,
            regionIDs: [],
            store: store,
            globals: world.globalResolution(defaults: defaults)
        )
        #expect(WeatherSelection.pick(from: after, seed: 7) == FormID(0x200))
    }

    @Test func weatherSystemAdoptsAResolutionAndRerolls() throws {
        let defaults = try Self.globalStore()
        let system = try WeatherSystem(store: Self.weatherStore(), worldspaceFormID: 0x500)
        let world = WorldStateStore()
        world.setGlobal(100_000, formID: Self.rainChanceID, defaults: defaults)
        system.setGlobalResolution(world.globalResolution(defaults: defaults))
        // Rain now dominates the pool by five orders of magnitude, so the
        // reroll the setter performs must land on it.
        #expect(system.currentWeatherID == FormID(0x200))
    }

    // MARK: - Fixtures

    private static func weatherStore() throws -> WeatherStore {
        try WeatherStore(file: ESMFile(data: plugin()))
    }

    private static func globalStore() throws -> GlobalStore {
        try GlobalFixture.store(GlobalFixture.record(
            formID: 0x0100_0800,
            editorID: "WeatherChanceRain",
            type: .short,
            value: 25
        ))
    }

    /// Two weathers, one climate whose rain entry carries a chance global, and
    /// one worldspace pointing at that climate.
    private static func plugin() -> Data {
        var wlst = Data()
        wlst.appendUInt32(0x100) // clear
        wlst.appendUInt32(90)
        wlst.appendUInt32(0) // no global
        wlst.appendUInt32(0x200) // rain
        wlst.appendUInt32(10)
        wlst.appendUInt32(0x0100_0800) // chance global
        let climate = ESMFixture.record(
            "CLMT",
            formID: 0x300,
            data: ESMFixture.field("EDID", ESMFixture.zstring("TestClimate"))
                + ESMFixture.field("WLST", wlst)
        )
        var cnam = Data()
        cnam.appendUInt32(0x300)
        let world = ESMFixture.record(
            "WRLD",
            formID: 0x500,
            data: ESMFixture.field("EDID", ESMFixture.zstring("TestWorld"))
                + ESMFixture.field("CNAM", cnam)
        )
        return ESMFixture.tes4()
            + ESMFixture.topGroup("WTHR", contents: weather(0x100) + weather(0x200))
            + ESMFixture.topGroup("CLMT", contents: climate)
            + ESMFixture.topGroup("WRLD", contents: world)
    }

    private static func weather(_ formID: UInt32) -> Data {
        ESMFixture.record(
            "WTHR",
            formID: formID,
            data: ESMFixture.field("EDID", ESMFixture.zstring("WTHR\(formID)"))
        )
    }
}
