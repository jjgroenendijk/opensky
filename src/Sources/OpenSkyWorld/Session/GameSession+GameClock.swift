// Game-clock glue: the per-frame advance, the timescale read, and the `timeOfDay`
// projection. `gameTime` is written and read on the main thread only.

import Foundation
import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyWorldInterface
public import OpenSkyWorldState

extension GameSession {
    /// Authoritative game clock. Setting it wholesale (save load, tests)
    /// resets the weather's elapsed-hours mark so a restored date does not
    /// register as months of weather time.
    public var gameClock: GameClock {
        get { gameTime.clock }
        set {
            gameTime.clock = newValue
            gameTime.weatherGameSecondsMark = nil
        }
    }

    /// Current timescale: the `TimeScale` global through the seam, the
    /// vanilla default 20 when nothing resolves it. Clamping happens in
    /// `GameClock.advance`.
    public var currentTimescale: Float {
        gameTime.globalResolution?.floatValue(editorID: GameClock.timescaleEditorID)
            ?? GameClock.defaultTimescale
    }

    /// Per-frame clock advance for the live draw loop. Menu pause freezes
    /// game time for free: the frame clock returns zero while paused and
    /// carries no jump on resume. The offscreen path deliberately never calls
    /// this, so a fixed clock renders deterministically.
    public func advanceGameClockFromWallClock() {
        gameTime.advanceRealTime(to: renderer.wallClock.now)
        let delta = gameTime.frameClock.advance(
            to: renderer.wallClock.now, paused: worldSimPaused
        )
        gameTime.clock.advance(wallDelta: delta, timescale: currentTimescale)
    }

    /// Per-frame world simulation tick, after the clock advances, so a script sees this
    /// frame's time. While paused `worldSimClock` returns zero, which is no advance.
    public func updateWorldSimFromWallClock() {
        let delta = worldSimClock.advance(
            to: renderer.wallClock.now, paused: worldSimPaused
        )
        updateWorldSim(deltaTime: delta * effectiveWorldTimeScale)
    }

    /// Seconds of menu pause since the last call; zero while the world runs.
    public func consumeMenuTime() -> Float {
        menuTimeClock.advance(to: renderer.wallClock.now, paused: !worldSimPaused)
    }

    /// Times only the world callback, excluding the renderer clock advance.
    /// Both the live and offscreen loops use this seam so the fly benchmark
    /// measures the same Papyrus VM work the shipping frame loop performs.
    public func updateWorldSim(deltaTime: Float) {
        assetDrains(())
        guard !worldTick.isEmpty else {
            lastScriptUpdateMS = 0
            return
        }
        let started = Stopwatch()
        worldTick(deltaTime)
        lastScriptUpdateMS =
            started.milliseconds
    }

    /// Game hours elapsed since the previous call, from the clock's own
    /// motion (advancement and forward scrubs alike). Backward scrubs count
    /// zero and a single step is capped at one day, preserving the bounds the
    /// old wrap heuristic enforced.
    public func consumeElapsedGameHours() -> Float {
        defer { gameTime.weatherGameSecondsMark = gameTime.clock.totalGameSeconds }
        guard let mark = gameTime.weatherGameSecondsMark else { return 0 }
        let hours = (gameTime.clock.totalGameSeconds - mark) / GameClock.secondsPerHour
        return Float(min(max(0, hours), 24))
    }
}
