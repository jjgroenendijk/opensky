// The image-space context of the current weather blend. See
// docs/formats/image-spaces.md, section "Resolution".

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering

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
