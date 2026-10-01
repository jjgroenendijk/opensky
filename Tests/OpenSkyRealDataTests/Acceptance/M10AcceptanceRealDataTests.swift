// Weather and time acceptance on the real install. It checks what the synthetic
// suite cannot: the plugins define `TimeScale` and the clock globals, a
// `TimeScale` override reaches the renderer, and Tamriel's climate rerolls every
// six game hours. It decodes records only (no cell, no archive, no render), so
// it stays light. The report in `logs/` holds counts and editor IDs only.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import Testing

struct M10AcceptanceRealDataTests {
    /// The gate's first sentence against the installed master: with the clock
    /// running at an elevated timescale written through the real `TimeScale`
    /// global, Tamriel's weather changes only on six-game-hour boundaries, and
    /// the clock, the `GameHour` projection and the panel's clock readout all
    /// describe the same instant at the end of the run.
    @Test(.enabled(if: RealDataEnvironment.canRender)) @MainActor
    func weatherAndTimeStaySynchronizedAgainstTheInstalledMaster() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
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
            M10AcceptanceClock.fastTimescale, formID: timescaleID, defaults: defaults
        ))
        let overriddenTimescale = try #require(
            session.resolution().floatValue(editorID: GameClock.timescaleEditorID)
        )
        #expect(overriddenTimescale == M10AcceptanceClock.fastTimescale)

        let system = try #require(
            WeatherSystem(file: file, worldspaceEditorID: FirstRenderCell.worldspaceEditorID),
            "Skyrim.esm carries no weather data"
        )
        system.setGlobalResolution(session.resolution())
        try Self.showAContrastingWeather(system)
        let run = Self.run(system, session: session, timescale: overriddenTimescale)

        #expect(run.elapsedGameHours == M10AcceptanceClock.totalGameHours)
        #expect(!run.changePoints.isEmpty, "Tamriel's weather never changed across the run")
        for point in run.changePoints {
            #expect(
                point.truncatingRemainder(dividingBy: WeatherSystem.rerollGameHours) == 0,
                "weather changed at \(point) game hours, off the reroll cadence"
            )
        }

        // The three readings the gate names, on real records.
        let clock = session.clock
        #expect(clock.hourOfDay == M10AcceptanceClock.endHour)
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

    /// Shows a weather the automatic pick never chooses, then resumes automatic
    /// selection. Tamriel's pool always lands on one weather, so only a start
    /// outside the pool makes the first reroll visible.
    @MainActor
    private static func showAContrastingWeather(_ system: WeatherSystem) throws {
        system.update(deltaTime: 100, hour: M10AcceptanceClock.startHour)
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
        [INFO] clock: \(M10AcceptanceClock.steps) steps of \
        \(M10AcceptanceClock.wallStep) real seconds = \(run.elapsedGameHours) game hours; \
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
            holder.clock = GameClock(hour: M10AcceptanceClock.startHour)
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
            box.clock.advance(wallDelta: M10AcceptanceClock.wallStep, timescale: timescale)
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
        if let weather {
            result.observedWeatherIDs.insert(weather)
        }
        for _ in 0 ..< M10AcceptanceClock.steps {
            let elapsed = session.advance(timescale)
            result.elapsedGameHours += elapsed
            result.lastResolvedHour = session.clock.hourOfDay
            system.update(
                deltaTime: M10AcceptanceClock.wallStep,
                hour: result.lastResolvedHour,
                elapsedGameHours: elapsed
            )
            guard system.currentWeatherID != weather else { continue }
            weather = system.currentWeatherID
            if let weather {
                result.observedWeatherIDs.insert(weather)
            }
            result.changePoints.append(result.elapsedGameHours)
        }
        return result
    }

    private static var logs: URL {
        get throws { try RepositoryLogs.directory() }
    }

    private static func write(_ report: String) throws {
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try report.write(
            to: logs.appending(path: "m10-acceptance.log"), atomically: true, encoding: .utf8
        )
        print(report)
    }
}
