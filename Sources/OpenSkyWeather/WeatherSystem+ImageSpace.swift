// The image-space context of the current weather blend. See
// docs/formats/image-spaces.md, section "Resolution".

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRenderCore

nonisolated extension WeatherSystem {
    /// The `IMSP` links of every weather in the blend, weighted, at `hour`.
    public func imageSpaceContext(hour: Float) -> ImageSpaceContext {
        let weathers = blendedWeathers.map {
            WeightedWeatherImageSpaces(
                imageSpaces: store.weather($0.weather)?.sky.imageSpaces,
                weight: $0.weight
            )
        }
        guard !weathers.isEmpty else { return .none }
        return .exterior(weathers: weathers, timeOfDay: timeOfDayWeights(hour: hour))
    }
}

nonisolated extension WeatherSystem {
    /// The `HNAM` volumetric light of the weather blend at `hour`; `records` resolves
    /// the links as spelled in `plugin`.
    public func volumetricLight(
        hour: Float, records: EffectRecordStore, plugin: String
    ) -> VolumetricLightValues {
        let weathers = blendedWeathers.map {
            (links: store.weather($0.weather)?.sky.volumetricLighting, weight: $0.weight)
        }
        return VolumetricLightValues.resolve(
            weathers: weathers, timeOfDay: timeOfDayWeights(hour: hour)
        ) { records.volumetricLighting.resolve($0, fromPlugin: plugin)?.record }
    }
}
