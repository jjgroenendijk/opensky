// The rings on the water: splashes, waders, and how long a ring lives.

import Foundation
import OpenSkyFormatsESM
@testable import OpenSkyRenderCore
import Testing

struct WaterRippleFieldTests {
    @Test func aRingAgesAndDropsOutAfterItsLife() {
        var field = WaterRippleField()
        field.add(at: SIMD3(10, 20, 5), strength: 1, time: 2)
        #expect(field.live(at: 3) == [SIMD4(10, 20, 1, 1)])
        #expect(field.live(at: 2 + WaterRippleField.lifetime + 0.1).isEmpty)
    }

    @Test func onlyTheNewestRingsStay() {
        var field = WaterRippleField()
        for index in 0 ..< WaterRippleField.limit + 3 {
            field.add(at: SIMD3(Float(index), 0, 0), strength: 0.5, time: 0)
        }
        let live = field.live(at: 0.5)
        #expect(live.count == WaterRippleField.limit)
        #expect(live.first?.x == 3)
    }

    @Test func aWaderStartsARingEachStep() {
        var field = WaterRippleField()
        field.wade(.player, at: SIMD3(0, 0, 0), time: 0)
        field.wade(.player, at: SIMD3(10, 0, 0), time: 0.1)
        #expect(field.ripples.count == 1)
        field.wade(.player, at: SIMD3(WaterRippleField.wakeSpacing, 0, 0), time: 0.2)
        #expect(field.ripples.count == 2)
        #expect(field.ripples.last?.strength == WaterRippleField.wakeStrength)
        field.keepWaders([])
        field.wade(.player, at: SIMD3(WaterRippleField.wakeSpacing + 1, 0, 0), time: 0.3)
        #expect(field.ripples.count == 3)
    }
}
