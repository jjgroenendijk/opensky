// A ward blocks what comes from its front arc of about 90 degrees.

@testable import OpenSkyMagic
import Testing

struct WardArcTests {
    @Test
    func aSourceAheadIsCovered() {
        #expect(WardArc.covers(holder: .zero, facing: 0, source: SIMD2(100, 0)))
        #expect(WardArc.covers(holder: .zero, facing: 0, source: SIMD2(100, 90)))
    }

    @Test
    func aSourceToTheSideOrBehindIsNot() {
        #expect(!WardArc.covers(holder: .zero, facing: 0, source: SIMD2(100, 110)))
        #expect(!WardArc.covers(holder: .zero, facing: 0, source: SIMD2(-100, 0)))
    }

    @Test
    func aSourceOnTheHolderCountsAsAhead() {
        #expect(WardArc.covers(holder: SIMD2(5, 5), facing: 1, source: SIMD2(5, 5)))
    }
}
