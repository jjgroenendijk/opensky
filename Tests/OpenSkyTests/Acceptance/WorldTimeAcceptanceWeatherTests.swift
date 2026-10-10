// Weather and time stay in sync: at a high timescale, weather changes only on a
// `WeatherSystem.rerollGameHours` boundary and at least one change happens.
// Counting changes would fail when a reroll picks the same weather. Sky hour,
// clock readout, and `GameHour` must agree. Real-data half:
// `WorldTimeAcceptanceRealDataTests.swift`.

import AppKit
import Foundation
@testable import OpenSky
import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
@testable import OpenSkyWorldState
import Testing

extension WorldTimeAcceptanceTests {
    // MARK: Step 8 — weather transitions fire from real elapsed game hours

    /// Forty-five game hours at a timescale of 3600 — one game hour per real
    /// second — driven half a real second at a time. Every weather change lands
    /// on a six-game-hour boundary, and at the end the clock, the `GameHour`
    /// projection, the hour the weather system was resolved at, and the panel's
    /// own readout all agree on 05:00.
    @Test @MainActor
    func weatherRerollsOnGameHourBoundariesWhileTheClockRunsFast() throws {
        let defaults = try Self.weatherTimeGlobals()
        var clock = GameClock(hour: WorldTimeAcceptanceClock.startHour)
        let timescale = try #require(
            GlobalResolution(defaults: defaults, clock: clock)
                .floatValue(editorID: GameClock.timescaleEditorID)
        )
        #expect(timescale == WorldTimeAcceptanceClock.fastTimescale)

        let system = try WeatherSystem(store: Self.weatherStore(), worldspaceFormID: 0x500)
        system.update(deltaTime: 100, hour: clock.hourOfDay) // settle the initial pick
        var weather = system.currentWeatherID
        #expect(weather != nil, "the fixture worldspace resolves no weather at all")

        var changePoints: [Float] = []
        var elapsedTotal: Float = 0
        var lastResolvedHour = clock.hourOfDay
        for _ in 0 ..< WorldTimeAcceptanceClock.steps {
            let before = clock.totalGameSeconds
            clock.advance(wallDelta: WorldTimeAcceptanceClock.wallStep, timescale: timescale)
            let elapsed = Float((clock.totalGameSeconds - before) / GameClock.secondsPerHour)
            #expect(elapsed == WorldTimeAcceptanceClock.gameHoursPerStep)
            elapsedTotal += elapsed
            lastResolvedHour = clock.hourOfDay
            system.update(
                deltaTime: WorldTimeAcceptanceClock.wallStep, hour: lastResolvedHour,
                elapsedGameHours: elapsed
            )
            if system.currentWeatherID != weather {
                weather = system.currentWeatherID
                changePoints.append(elapsedTotal)
            }
        }

        #expect(elapsedTotal == WorldTimeAcceptanceClock.totalGameHours)
        #expect(!changePoints.isEmpty, "no weather ever changed, so no reroll can be observed")
        for point in changePoints {
            #expect(
                point.truncatingRemainder(dividingBy: WeatherSystem.rerollGameHours) == 0,
                "weather changed at \(point) game hours, off the reroll cadence"
            )
        }
        try Self.expectClockAgreement(clock, defaults: defaults, resolvedHour: lastResolvedHour)
    }

    /// The same run through the real renderer seam the app uses:
    /// `Renderer.consumeElapsedGameHours()` feeding
    /// `WeatherSystem.update(deltaTime:hour:elapsedGameHours:)`, with the
    /// timescale read through `Renderer.currentTimescale` off the global
    /// resolution rather than passed in.
    @Test(.enabled(if: ShadowSceneFixture.hasMetal4Device)) @MainActor
    func theRendererFeedsWeatherTheClocksOwnElapsedGameHours() throws {
        let device = try #require(ShadowSceneFixture.device)
        let renderer = try ShadowSceneFixture.makeRenderer(device: device)
        let defaults = try Self.weatherTimeGlobals()
        renderer.gameClock = GameClock(hour: WorldTimeAcceptanceClock.startHour)
        renderer.gameTime.globalResolution = GlobalResolution(
            defaults: defaults, clock: renderer.gameClock
        )
        #expect(renderer.currentTimescale == WorldTimeAcceptanceClock.fastTimescale)

        // Setting the clock wholesale clears the elapsed-hours mark, so the
        // first read is zero: a restored save must not age months of weather.
        #expect(renderer.consumeElapsedGameHours() == 0)

        let system = try WeatherSystem(store: Self.weatherStore(), worldspaceFormID: 0x500)
        system.update(deltaTime: 100, hour: renderer.timeOfDay)
        var weather = system.currentWeatherID
        var changePoints: [Float] = []
        var elapsedTotal: Float = 0
        for _ in 0 ..< WorldTimeAcceptanceClock.steps {
            renderer.gameTime.clock.advance(
                wallDelta: WorldTimeAcceptanceClock.wallStep, timescale: renderer.currentTimescale
            )
            let elapsed = renderer.consumeElapsedGameHours()
            #expect(elapsed == WorldTimeAcceptanceClock.gameHoursPerStep)
            elapsedTotal += elapsed
            system.update(
                deltaTime: WorldTimeAcceptanceClock.wallStep, hour: renderer.timeOfDay,
                elapsedGameHours: elapsed
            )
            if system.currentWeatherID != weather {
                weather = system.currentWeatherID
                changePoints.append(elapsedTotal)
            }
        }

        #expect(elapsedTotal == WorldTimeAcceptanceClock.totalGameHours)
        #expect(!changePoints.isEmpty)
        for point in changePoints {
            #expect(point.truncatingRemainder(dividingBy: WeatherSystem.rerollGameHours) == 0)
        }
        // `timeOfDay` is the projection the sky shader and the weather blend
        // both read, so this is the sky hour agreeing with the clock.
        #expect(renderer.timeOfDay == renderer.gameClock.hourOfDay)
        try Self.expectClockAgreement(
            renderer.gameClock, defaults: defaults, resolvedHour: renderer.timeOfDay
        )
    }

    /// A paused world elapses no game hours, so weather cannot reroll behind a
    /// menu. The same wall time passes; only the clock stops.
    @Test @MainActor
    func aPausedWorldElapsesNoGameHoursSoWeatherNeverRerolls() throws {
        let system = try WeatherSystem(store: Self.weatherStore(), worldspaceFormID: 0x500)
        system.update(deltaTime: 100, hour: WorldTimeAcceptanceClock.startHour)
        let settled = system.currentWeatherID
        var clock = FrameSimClock()
        var elapsedTotal: Float = 0
        for step in 1 ... WorldTimeAcceptanceClock.steps {
            let delta = clock.advance(
                to: Double(step) * Double(WorldTimeAcceptanceClock.wallStep),
                paused: true
            )
            #expect(delta == 0)
            system.update(
                deltaTime: WorldTimeAcceptanceClock.wallStep,
                hour: WorldTimeAcceptanceClock.startHour,
                elapsedGameHours: delta
            )
            elapsedTotal += delta
        }
        #expect(elapsedTotal == 0)
        #expect(system.currentWeatherID == settled)
        #expect(system.transitionFraction == 1)
    }

    // MARK: Shared assertions

    /// The three readings the gate names, checked against one another: the
    /// clock, the `GameHour` global projection, and the World > Runtime State
    /// clock readout read back by accessibility identifier.
    @MainActor
    static func expectClockAgreement(
        _ clock: GameClock, defaults: GlobalStore, resolvedHour: Float
    ) throws {
        #expect(clock.hourOfDay == WorldTimeAcceptanceClock.endHour)
        #expect(resolvedHour == clock.hourOfDay)
        let resolution = GlobalResolution(defaults: defaults, clock: clock)
        #expect(resolution.floatValue(editorID: GameClock.TimeGlobal.gameHour.editorID)
            == clock.hourOfDay)

        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let engine = FakeRuntimeStateProvider()
        engine.runtimeStateClock = RuntimeStateClockSnapshot(
            clock: clock, timescale: WorldTimeAcceptanceClock.fastTimescale, isPaused: false
        )
        panel.provider = engine
        panel.startInspecting()
        defer { panel.stopInspecting() }
        let readout = try #require(
            runtimeStateReadout("RuntimeStateTimeStatsLabel", in: panel.view)
        )
        #expect(readout.contains("05:00  19 Last Seed, 4E 201"))
        #expect(readout.contains("Timescale: 3600"))
    }

    // MARK: Synthetic engine state

    // The clock plan these steps run on — timescale, step size and start hour — is
    // shared with the real-data half, so it lives in `WorldTimeAcceptanceClock`
    // (`Tests/HostedTestSupport/Acceptance/WorldTimeAcceptanceFixture.swift`).

    /// `TimeScale` at 3600 plus the five clock-owned time globals. Invented
    /// FormIDs; the editor IDs are the vanilla spellings the engine matches on.
    static func weatherTimeGlobals() throws -> GlobalStore {
        var records = GlobalFixture.record(
            formID: 0x0900, editorID: GameClock.timescaleEditorID, type: .float,
            value: WorldTimeAcceptanceClock.fastTimescale
        )
        for (index, timeGlobal) in GameClock.TimeGlobal.allCases.enumerated() {
            records += GlobalFixture.record(
                formID: UInt32(0x0901 + index), editorID: timeGlobal.editorID,
                type: .float, value: 0
            )
        }
        return try GlobalFixture.store(records)
    }

    /// Two weathers with an even climate chance, so a reroll has something to
    /// change to, and one worldspace pointing at that climate.
    static func weatherStore() throws -> WeatherStore {
        var wlst = Data()
        for weatherID in [UInt32(0x100), 0x200] {
            wlst.appendUInt32(weatherID)
            wlst.appendUInt32(50)
            wlst.appendUInt32(0) // no chance global
        }
        let climate = ESMFixture.record(
            "CLMT",
            formID: 0x300,
            data: ESMFixture.field("EDID", ESMFixture.zstring("WorldTimeClimate"))
                + ESMFixture.field("WLST", wlst)
        )
        var cnam = Data()
        cnam.appendUInt32(0x300)
        let world = ESMFixture.record(
            "WRLD",
            formID: 0x500,
            data: ESMFixture.field("EDID", ESMFixture.zstring("WorldTimeWorld"))
                + ESMFixture.field("CNAM", cnam)
        )
        let weathers = weatherRecord(0x100) + weatherRecord(0x200)
        let plugin = ESMFixture.tes4()
            + ESMFixture.topGroup("WTHR", contents: weathers)
            + ESMFixture.topGroup("CLMT", contents: climate)
            + ESMFixture.topGroup("WRLD", contents: world)
        return try WeatherStore(file: ESMFile(data: plugin))
    }

    private static func weatherRecord(_ formID: UInt32) -> Data {
        ESMFixture.record(
            "WTHR",
            formID: formID,
            data: ESMFixture.field("EDID", ESMFixture.zstring("WorldTimeWeather\(formID)"))
        )
    }
}
