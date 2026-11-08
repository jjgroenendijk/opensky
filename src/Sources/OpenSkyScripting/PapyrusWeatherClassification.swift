// `Weather.GetClassification`: the number a script reads for a weather's precipitation.

public import OpenSkyFormatsESM

nonisolated extension Weather.Precipitation {
    /// CK wiki "GetClassification - Weather": -1 none, 0 pleasant, 1 cloudy, 2 rainy, 3 snow.
    public var papyrusClassification: Int32 {
        switch self {
        case .none: -1
        case .pleasant: 0
        case .cloudy: 1
        case .rainy: 2
        case .snow: 3
        }
    }
}
