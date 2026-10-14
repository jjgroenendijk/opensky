// The port the `Weather` natives change the sky through. The app's script adapter
// conforms over the weather system. See docs/engine/weather.md.

import Foundation
import OpenSkyFormatsESM

@MainActor
public protocol PapyrusWeatherControlling: AnyObject {
    /// The weather the sky shows or is moving to. Nil before the first weather.
    var currentWeather: ReferenceKey? { get }

    /// Moves to `weather`. A held weather stays until released; `instant` skips the
    /// blend. False when the form is no `WTHR`.
    @discardableResult
    func setWeather(_ weather: ReferenceKey, held: Bool, instant: Bool) -> Bool

    /// Ends a held weather, so the regions pick again.
    func releaseWeather()

    /// The candidates of the current regions and climate, in pick order.
    func candidateWeathers() -> [ReferenceKey]

    /// `GetClassification` codes: -1 none, 0 pleasant, 1 cloudy, 2 rainy, 3 snow.
    func classification(of weather: ReferenceKey) -> Int32?
}
