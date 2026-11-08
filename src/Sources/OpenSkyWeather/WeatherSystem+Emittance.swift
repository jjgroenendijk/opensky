// The `Effect Lighting` colour a region's weather gives to references whose `XEMI`
// names the region (docs/formats/nif-materials.md#effect-shapes).

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRenderCore
import simd

nonisolated extension WeatherSystem {
    /// Each region's `Effect Lighting` colour at `hour`. A region without a weather or
    /// colour is left out, so its references fall back to the scene light.
    public func regionEmittance(for regions: Set<UInt32>, hour: Float) -> [UInt32: SIMD3<Float>] {
        guard !regions.isEmpty else { return [:] }
        let weights = timeOfDayWeights(hour: hour)
        var colours: [UInt32: SIMD3<Float>] = [:]
        for id in regions {
            guard
                let region = store.region(FormID(id)),
                let weather = Self.emittanceWeather(of: region, active: currentWeatherID),
                let layer = store.weather(weather)?.colors(for: .effectLighting)
            else { continue }
            colours[id] = weights.blend(layer.sunrise, layer.day, layer.sunset, layer.night)
        }
        return colours
    }

    /// The game keeps a weather per region; OpenSky runs one. So a region takes the
    /// active weather when it lists it, else its most likely weather.
    static func emittanceWeather(of region: Region, active: FormID?) -> FormID? {
        if let active, region.weatherList.contains(where: { $0.weather == active }) {
            return active
        }
        return region.weatherList.max { $0.chance < $1.chance }?.weather
    }
}
