@testable import OpenSkyPlayer
import Testing

struct BorderRegionRuleTests {
    private let square: [[SIMD2<Float>]] = [[
        SIMD2(0, 0), SIMD2(100, 0), SIMD2(100, 100), SIMD2(0, 100)
    ]]

    @Test func aStepThatLeavesTheOutlineIsHeld() {
        #expect(BorderRegionRule.allows(from: SIMD2(50, 50), to: SIMD2(60, 50), outlines: square))
        #expect(!BorderRegionRule.allows(from: SIMD2(99, 50), to: SIMD2(101, 50), outlines: square))
    }

    @Test func aPlayerOutsideOrAWorldWithoutBordersMovesFreely() {
        #expect(BorderRegionRule.allows(from: SIMD2(150, 50), to: SIMD2(160, 50), outlines: square))
        #expect(BorderRegionRule.allows(from: SIMD2(150, 50), to: SIMD2(50, 50), outlines: square))
        #expect(BorderRegionRule.allows(from: SIMD2(99, 50), to: SIMD2(101, 50), outlines: []))
    }

    @Test func aConcaveOutlineCountsItsNotch() {
        let notched: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(100, 0), SIMD2(100, 100), SIMD2(60, 100),
            SIMD2(60, 40), SIMD2(40, 40), SIMD2(40, 100), SIMD2(0, 100)
        ]
        #expect(BorderRegionRule.contains(SIMD2(20, 80), outline: notched))
        #expect(!BorderRegionRule.contains(SIMD2(50, 80), outline: notched))
    }
}
