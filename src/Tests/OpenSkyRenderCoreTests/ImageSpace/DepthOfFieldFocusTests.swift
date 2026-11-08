// The centre weight of the focus: 0.6 while the view moves, then after half a second still
// it eases to 1.6 outdoors or 1.0 indoors over one second.

import Foundation
@testable import OpenSkyRenderCore
import simd
import Testing

struct DepthOfFieldFocusTests {
    private static func still(seconds: Float, interior: Bool = false) -> DepthOfFieldFocus {
        var focus = DepthOfFieldFocus()
        var left = seconds
        focus.advance(angles: .zero, position: .zero, interior: interior, seconds: 0)
        while left > 0 {
            focus.advance(
                angles: .zero,
                position: .zero,
                interior: interior,
                seconds: min(left, 0.1)
            )
            left -= 0.1
        }
        return focus
    }

    @Test func weightWaitsThenEasesToTheStillValue() {
        #expect(Self.still(seconds: 0.4).centreWeight == 0.6)
        let half = Self.still(seconds: 1.0).centreWeight
        #expect(abs(half - (0.6 + 1.0 * sin(Float.pi / 4))) < 1e-3)
        #expect(abs(Self.still(seconds: 2).centreWeight - 1.6) < 1e-5)
        #expect(abs(Self.still(seconds: 2, interior: true).centreWeight - 1.0) < 1e-5)
    }

    @Test func turnOrMoveResetsTheWeight() {
        var focus = Self.still(seconds: 2)
        focus.advance(angles: SIMD3(0, 0, 0.01), position: .zero, interior: false, seconds: 0.1)
        #expect(abs(focus.centreWeight - 1.6) < 1e-5)
        focus.advance(angles: SIMD3(0, 0, 0.1), position: .zero, interior: false, seconds: 0.1)
        #expect(focus.centreWeight == 0.6)
        focus = Self.still(seconds: 2)
        focus.advance(angles: .zero, position: SIMD3(6, 0, 0), interior: false, seconds: 0.1)
        #expect(focus.centreWeight == 0.6)
    }
}
