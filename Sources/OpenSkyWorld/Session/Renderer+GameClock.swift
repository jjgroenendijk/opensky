// Renderer-side game-clock glue (issue #164), split from Renderer.swift
// (file-length limits): the per-frame clock advance, the timescale read
// through the global seam, and the `timeOfDay` projection every existing
// consumer (shader uniform, weather blend, panel slider, tests) keeps using.
//
// Threading: `gameTime` follows the same rule the old `timeOfDay` float did —
// written from the main thread (panel scrubs, global writes, save restore) and
// read in `draw(in:)`, which MTKView also runs on the main thread.

import Foundation
import OpenSkyRendering
import OpenSkyWorldState

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
}

extension Renderer {
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
        let delta = gameTime.frameClock.advance(
            to: wallClock.now, paused: worldSimPaused
        )
        gameTime.clock.advance(wallDelta: delta, timescale: currentTimescale)
    }

    /// Per-frame world simulation tick (issue #171). Runs immediately after
    /// the game clock advances, so a script waking on game time sees this
    /// frame's clock. Menu pause is honoured through the clock rather than a
    /// branch: `worldSimClock` returns zero while paused, and the world
    /// runtime's fixed-step accumulator treats a zero delta as no advance.
    public func updateWorldSimFromWallClock() {
        let delta = worldSimClock.advance(
            to: wallClock.now, paused: worldSimPaused
        )
        updateWorldSim(deltaTime: delta)
    }

    /// Times only the world callback, excluding the renderer clock advance.
    /// Both the live and offscreen loops use this seam so the fly benchmark
    /// measures the same Papyrus VM work the shipping frame loop performs.
    public func updateWorldSim(deltaTime: Float) {
        guard let onWorldUpdate else {
            lastScriptUpdateMS = 0
            return
        }
        let started = DispatchTime.now().uptimeNanoseconds
        onWorldUpdate(deltaTime)
        lastScriptUpdateMS =
            Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
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
