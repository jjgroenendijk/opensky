// The sun, moons, stars, and aurora of the current climate and weather blend.

import OpenSkyGameData
public import OpenSkyRenderCore

nonisolated extension WeatherSystem {
    public func celestialSky(
        hour: Float,
        daysPassed: Float,
        settings: SkySettings
    ) -> CelestialSky {
        CelestialSky.resolve(
            hour: hour,
            daysPassed: daysPassed,
            climate: climate,
            weathers: blendedWeathers.compactMap { entry in
                store.weather(entry.weather).map { ($0, entry.weight) }
            },
            settings: settings
        )
    }
}
