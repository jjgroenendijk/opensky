import Foundation
import OpenSkyFormatsCore
import OpenSkyGameData
public import OpenSkyRenderCore
public import OpenSkyWorldState

/// The renderer's game-time state, grouped so `Renderer` carries one stored
/// property instead of four.
nonisolated public struct RendererGameTime: Sendable {
    /// Authoritative game clock (docs/engine/game-clock.md).
    public var clock = GameClock()
    /// Wall-clock delta source for the clock, paused in menu mode like every
    /// other sim clock.
    public var frameClock = FrameSimClock()
    /// Seam the per-frame `TimeScale` read goes through. nil (no game data,
    /// offscreen tests, CLI) -> the vanilla default 20.
    public var globalResolution: GlobalResolution?
    /// `totalGameSeconds` at the last weather update, so the weather runtime
    /// receives real elapsed game hours instead of reconstructing them from
    /// hour deltas. nil until the first update.
    public var weatherGameSecondsMark: Double?
    /// Real seconds the live frames ran, menus included. Each frame counts at most
    /// `maxDelta`, so a stall such as a save or a load does not count, as in the game.
    public private(set) var realSecondsRun: Double = 0
    private var realTimeClock = FrameSimClock()
    /// Clock moves that crossed midnight since `consumeDaysPassed`. A move counts once,
    /// however many days it jumps, as the game's day-passed event does.
    public private(set) var pendingDaysPassed = 0

    /// Runs the clock forward as time passes, by frames or by resting. Setting `clock`
    /// itself, as a load or a set time does, passes no day.
    public mutating func passTime(wallDelta: Float, timescale: Float) {
        var moved = clock
        moved.advance(wallDelta: wallDelta, timescale: timescale)
        passTime(to: moved)
    }

    public mutating func passTime(to moved: GameClock) {
        if moved.dayNumber > clock.dayNumber {
            pendingDaysPassed += 1
        }
        clock = moved
    }

    /// Time that passes off screen, as fast travel or a jail term: the days pass, and the
    /// weather starts over, as a set clock does.
    public mutating func skipTime(to moved: GameClock) {
        passTime(to: moved)
        weatherGameSecondsMark = nil
    }

    public mutating func consumeDaysPassed() -> Int {
        defer { pendingDaysPassed = 0 }
        return pendingDaysPassed
    }

    /// One live frame of real time, read from the wall clock the frame clock reads.
    public mutating func advanceRealTime(to now: Double) {
        realSecondsRun += Double(realTimeClock.advance(to: now, paused: false))
    }

    public init(
        clock: GameClock = GameClock(),
        frameClock: FrameSimClock = FrameSimClock(),
        globalResolution: GlobalResolution? = nil,
        weatherGameSecondsMark: Double? = nil,
        realSecondsRun: Double = 0
    ) {
        self.clock = clock
        self.frameClock = frameClock
        self.globalResolution = globalResolution
        self.weatherGameSecondsMark = weatherGameSecondsMark
        self.realSecondsRun = realSecondsRun
    }
}
