// M10 acceptance against the user's read-only Skyrim SE install (issue #166):
// the real-data half of "weather and time stay synchronized".
//
// The synthetic suite in `M10AcceptanceWeatherTests.swift` proves the mechanism
// over a two-weather fixture plugin. What it cannot prove is that the shipped
// plugins actually define the globals the mechanism depends on — `TimeScale` and
// the five clock-owned time globals — that a `TimeScale` override written
// through the runtime globals layer reaches `Renderer.currentTimescale`'s seam,
// or that Tamriel's real climate reroll obeys the six-game-hour cadence rather
// than the fixture's. All three need real records, so they live here.
//
// Deliberately light: the GLOB, WTHR, CLMT, REGN and WRLD groups of Skyrim.esm
// are decoded from a memory-mapped file. No cell is built, no archive is opened
// and nothing renders, which keeps this well inside the RSS watchdog
// `tools/realtest.sh` runs.
//
// No game-derived bytes are written anywhere: the report goes to gitignored
// `logs/` and names counts and editor IDs only.

import Foundation
@testable import opensky
import Testing

struct M10AcceptanceRealDataTests {
    /// Env-gated exactly like `M10StateAcceptanceRealDataTests`: without
    /// `OPENSKY_DATA_ROOT` the test skips instead of consulting the Steam
    /// default. No Metal device is needed — nothing here renders.
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    private static var canRun: Bool {
        dataRoot != nil
    }

    /// The gate's first sentence against the installed master: with the clock
    /// running at an elevated timescale written through the real `TimeScale`
    /// global, Tamriel's weather changes only on six-game-hour boundaries, and
    /// the clock, the `GameHour` projection and the panel's clock readout all
    /// describe the same instant at the end of the run.
    @Test(.enabled(if: Self.canRun)) @MainActor
    func weatherAndTimeStaySynchronizedAgainstTheInstalledMaster() throws {
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let defaults = GlobalStore(file: file, pluginName: "Skyrim.esm")
        let timescaleID = try #require(
            defaults.formID(editorID: GameClock.timescaleEditorID),
            "Skyrim.esm defines no TimeScale global"
        )
        for timeGlobal in GameClock.TimeGlobal.allCases {
            #expect(
                defaults.global(editorID: timeGlobal.editorID) != nil,
                "Skyrim.esm defines no \(timeGlobal.editorID) global"
            )
        }

        let session = Self.Session(defaults: defaults)
        let authoredTimescale = try #require(
            session.resolution().floatValue(editorID: GameClock.timescaleEditorID)
        )
        #expect(session.world.setGlobal(
            M10AcceptanceTests.fastTimescale, formID: timescaleID, defaults: defaults
        ))
        let overriddenTimescale = try #require(
            session.resolution().floatValue(editorID: GameClock.timescaleEditorID)
        )
        #expect(overriddenTimescale == M10AcceptanceTests.fastTimescale)

        let system = try #require(
            WeatherSystem(file: file, worldspaceEditorID: FirstRenderCell.worldspaceEditorID),
            "Skyrim.esm carries no weather data"
        )
        system.setGlobalResolution(session.resolution())
        try Self.showAContrastingWeather(system)
        let run = Self.run(system, session: session, timescale: overriddenTimescale)

        #expect(run.elapsedGameHours == M10AcceptanceTests.totalGameHours)
        #expect(!run.changePoints.isEmpty, "Tamriel's weather never changed across the run")
        for point in run.changePoints {
            #expect(
                point.truncatingRemainder(dividingBy: WeatherSystem.rerollGameHours) == 0,
                "weather changed at \(point) game hours, off the reroll cadence"
            )
        }

        // The three readings the gate names, on real records.
        let clock = session.clock
        #expect(clock.hourOfDay == M10AcceptanceTests.endHour)
        #expect(run.lastResolvedHour == clock.hourOfDay)
        let projected = try #require(
            session.resolution().floatValue(editorID: GameClock.TimeGlobal.gameHour.editorID)
        )
        #expect(projected == clock.hourOfDay)
        let sample = RuntimeStateClockSnapshot(
            clock: clock, timescale: overriddenTimescale, isPaused: false
        )
        #expect(sample.timeText == "05:00")

        try Self.write("""
        [INFO] data root: \(root.dataURL.lastPathComponent) (source \(root.source))
        [INFO] Skyrim.esm globals: \(defaults.count) decoded; \
        TimeScale plugin default \(RuntimeStateNumberText.text(authoredTimescale)), \
        session override \(RuntimeStateNumberText.text(overriddenTimescale))
        \(Self.report(run, system: system, sample: sample, projection: projected))
        """)
    }

    // MARK: - Support

    /// Puts a weather on screen that the automatic pick will not choose, then
    /// resumes automatic selection with the reroll counter at zero.
    ///
    /// Without this the run has nothing to observe. Tamriel's authored chances
    /// are lopsided enough that every automatic pick across the run lands on the
    /// same weather, and a reroll that reselects the weather already showing is
    /// by design a no-op — so "the weather never changed" would say nothing
    /// about whether the cadence fired. Starting from a weather the pool will
    /// not return makes the first reroll observable, and it must land exactly on
    /// the six-game-hour boundary.
    @MainActor
    private static func showAContrastingWeather(_ system: WeatherSystem) throws {
        system.update(deltaTime: 100, hour: M10AcceptanceTests.startHour)
        let automatic = try #require(system.currentWeatherID, "no automatic pick for Tamriel")
        let contrast = try #require(
            system.store.selectableWeathers().first { $0.formID != automatic },
            "Tamriel resolves only one selectable weather"
        )
        system.forceWeather(contrast.formID, transition: .instant)
        system.forceWeather(nil, transition: .instant)
        #expect(system.currentWeatherID == contrast.formID)
    }

    /// The run's own numbers, kept out of the test body so it stays inside the
    /// function-length limit.
    @MainActor
    private static func report(
        _ run: RunResult, system: WeatherSystem,
        sample: RuntimeStateClockSnapshot, projection: Float
    ) -> String {
        """
        [INFO] Tamriel weather pool: \(system.store.selectableWeathers().count) selectable \
        weathers; \(run.observedWeatherIDs.count) distinct weathers observed across the run
        [INFO] clock: \(M10AcceptanceTests.steps) steps of \
        \(M10AcceptanceTests.wallStep) real seconds = \(run.elapsedGameHours) game hours; \
        \(sample.timeText) \(sample.dateText), GameHour projection \(projection)
        [INFO] weather changes at game hours: \
        \(run.changePoints.map { String($0) }.joined(separator: ", ")) \
        (reroll cadence \(WeatherSystem.rerollGameHours))
        """
    }

    /// One real-data session: the installed plugin defaults, a store whose
    /// time-global writes drive the clock, and the clock itself — wired the way
    /// `GameViewController` wires them.
    @MainActor
    private struct Session {
        let world = WorldStateStore()
        let defaults: GlobalStore
        private let box = ClockHolder()

        init(defaults: GlobalStore) {
            self.defaults = defaults
            let holder = box
            holder.clock = GameClock(hour: M10AcceptanceTests.startHour)
            world.onTimeGlobalWrite = { timeGlobal, value in
                let previous = holder.clock.projectedValue(timeGlobal)
                holder.clock.setProjectedValue(value, for: timeGlobal)
                return previous
            }
        }

        var clock: GameClock {
            box.clock
        }

        func advance(_ timescale: Float) -> Float {
            let before = box.clock.totalGameSeconds
            box.clock.advance(wallDelta: M10AcceptanceTests.wallStep, timescale: timescale)
            return Float((box.clock.totalGameSeconds - before) / GameClock.secondsPerHour)
        }

        func resolution() -> GlobalResolution {
            world.globalResolution(defaults: defaults, clock: box.clock)
        }
    }

    private final class ClockHolder {
        var clock = GameClock()
    }

    private struct RunResult {
        var elapsedGameHours: Float = 0
        var lastResolvedHour: Float = 0
        var changePoints: [Float] = []
        var observedWeatherIDs: Set<FormID> = []
    }

    /// Drives the clock and the weather runtime together for the same number of
    /// steps the synthetic half uses, recording every game hour at which the
    /// selected weather changed.
    @MainActor
    private static func run(
        _ system: WeatherSystem, session: Session, timescale: Float
    ) -> RunResult {
        var result = RunResult()
        system.update(deltaTime: 100, hour: session.clock.hourOfDay)
        var weather = system.currentWeatherID
        weather.map { result.observedWeatherIDs.insert($0) }
        for _ in 0 ..< M10AcceptanceTests.steps {
            let elapsed = session.advance(timescale)
            result.elapsedGameHours += elapsed
            result.lastResolvedHour = session.clock.hourOfDay
            system.update(
                deltaTime: M10AcceptanceTests.wallStep,
                hour: result.lastResolvedHour,
                elapsedGameHours: elapsed
            )
            guard system.currentWeatherID != weather else { continue }
            weather = system.currentWeatherID
            weather.map { result.observedWeatherIDs.insert($0) }
            result.changePoints.append(result.elapsedGameHours)
        }
        return result
    }

    private static var logs: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "logs")
    }

    private static func write(_ report: String) throws {
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try report.write(
            to: logs.appending(path: "m10-acceptance.log"), atomically: true, encoding: .utf8
        )
        print(report)
    }
}
