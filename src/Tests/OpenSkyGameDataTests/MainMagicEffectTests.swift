// The main effect of a spell: the whole-number cost decides, and the earlier effect wins a tie.

@testable import OpenSkyGameData
import Testing

struct MainMagicEffectTests {
    @Test func theMainEffectIsTheCostliestOneNotSkipped() {
        #expect(MainMagicEffect.index(costs: [3.9, 3.2, 1], skipped: [false, false, false]) == 0)
        #expect(MainMagicEffect.index(costs: [2, 9, 4], skipped: [false, true, false]) == 2)
        #expect(MainMagicEffect.index(costs: [5, 5.5], skipped: [false, false]) == 0)
        #expect(MainMagicEffect.index(costs: [1], skipped: [true]) == nil)
    }

    @Test func aNegativeCostCountsAsZero() {
        #expect(MainMagicEffect.index(costs: [-4, 0], skipped: [false, false]) == 0)
    }
}
