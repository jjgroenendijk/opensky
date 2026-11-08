// `Weather.GetClassification` numbers each precipitation as the CK wiki gives them.

import OpenSkyFormatsESM
@testable import OpenSkyScripting
import Testing

struct PapyrusWeatherClassificationTests {
    @Test
    func eachPrecipitationHasItsNumber() {
        let all: [Weather.Precipitation] = [.none, .pleasant, .cloudy, .rainy, .snow]
        #expect(all.map(\.papyrusClassification) == [-1, 0, 1, 2, 3])
    }
}
