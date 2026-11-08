public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyRenderCore
public import OpenSkyWorldInterface
public import OpenSkyWorldState

/// What the world adapters use of `WeatherSystem`.
public protocol WeatherSystemPort: AnyObject {
    var currentWeatherID: FormID? { get }
    func forceWeather(_ weather: FormID?, transition: WeatherTransition)
    var forced: FormID? { get }
    func resumeAutomatic()
    func setGlobalResolution(_ resolution: GlobalResolution?, reroll shouldReroll: Bool)
    var store: WeatherStore { get }
    func timeOfDayWeights(hour: Float) -> TimeOfDayWeights

    var blendedWeathers: [(weather: FormID, weight: Float)] { get }
    var currentWeatherEditorID: String? { get }
}

/// The default arguments a protocol requirement cannot carry.
extension WeatherSystemPort {}
