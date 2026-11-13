// The behaviour gap sweep's classification: which tally entries match the game.

import OpenSkyBehavior
import Testing

struct BehaviorGapSweepTests {
    @Test func aConditionTheGameAlsoBlocksMatchesTheGame() {
        #expect(BehaviorTally.Gap.transitionConditionUnparsed.matchesGame)
        #expect(BehaviorTally.Gap.transitionConditionUnresolved.matchesGame)
        #expect(!BehaviorTally.Gap.unresolvedBehaviorReference.matchesGame)
    }

    @Test func aNewSweepHasNothingLeftOrUnreached() {
        let sweep = BehaviorGapSweep()
        #expect(sweep.unreachedClasses.isEmpty)
        #expect(sweep.leftClasses.isEmpty)
        #expect(sweep.graphCount == 0)
    }
}
