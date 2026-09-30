// The per-frame weather advance (M7.2.2), run by the game session between the
// world simulation and the renderer's own animation step.

import OpenSkyRendering

extension Renderer {
    /// Advances the weather runtime (transition + reroll accumulation) and
    /// caches this frame's resolved weather. No weather system -> the cache
    /// stays nil and the renderer behaves exactly as before (procedural sky,
    /// camera lighting). Cheap: two resolves + one blend. Reroll cadence is
    /// fed real elapsed game hours off the game clock (issue #164); a fixed
    /// clock — offscreen renders, CLI — therefore elapses none.
    public func updateWeather(deltaTime: Float) {
        guard weatherEnabled, let weather else {
            currentResolvedWeather = nil
            return
        }
        weather.update(
            deltaTime: max(deltaTime, 0),
            hour: timeOfDay,
            elapsedGameHours: consumeElapsedGameHours()
        )
        currentResolvedWeather = weather.resolvedWeather?.applyingStormSkyDarkening()
    }

    public func updateWeatherFromWallClock() {
        let delta = weatherClock.advance(to: wallClock.now, paused: worldSimPaused)
        updateWeather(deltaTime: delta)
    }
}
