// The per-frame weather advance, between the world simulation and the animation step.

import OpenSkyRendering

extension Renderer {
    /// Advances weather and caches this frame's resolve; nil without a weather system.
    /// Rerolls count real game hours, so a fixed clock (offscreen, CLI) never rerolls.
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
