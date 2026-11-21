// The four AI process levels: the level of an actor, the update intervals, the frame
// budget, and a pass that goes on from its saved place (docs/engine/ai-process-levels.md).

import OpenSkyAIPackages
import Testing

struct AIProcessLevelsTests {
    @Test func theLevelFollowsTheCellAndThe3D() {
        var facts = AIProcessFacts()
        #expect(AIProcessRule.level(facts) == .low)
        facts.cellLoaded = true
        #expect(AIProcessRule.level(facts) == .middleLow)
        facts.has3D = true
        #expect(AIProcessRule.level(facts) == .middleHigh)
        facts.cellAttached = true
        #expect(AIProcessRule.level(facts) == .high)
        facts.inPersistentCell = true
        facts.distanceToPlayer = 40961
        #expect(AIProcessRule.level(facts) == .middleLow)
        facts.isPlayerMount = true
        #expect(AIProcessRule.level(facts) == .high)
    }

    @Test func anActorWith3DInAnUnloadedCellKeepsItsLevel() {
        var facts = AIProcessFacts()
        facts.isForcedHigh = true
        #expect(AIProcessRule.level(facts) == nil)
    }

    @Test func theIntervalsFollowTheTimescale() {
        #expect(AIProcessLevel.high.updateSeconds(timescale: 20) == nil)
        #expect(AIProcessLevel.middleHigh.updateSeconds(timescale: 20) == 9)
        #expect(AIProcessLevel.middleLow.updateSeconds(timescale: 20) == 27)
        #expect(AIProcessLevel.low.updateSeconds(timescale: 20) == 54)
        #expect(AIProcessLevel.low.updateSeconds(timescale: 40) == 27)
        #expect(AIProcessLevel.allCases.map(\.name).count == 4)
    }

    @Test func anUpdateIsDueAtFirstAfterTheIntervalAndAfterMidnight() {
        #expect(AIProcessRule.isDue(now: 5, last: nil, interval: 9))
        #expect(AIProcessRule.isDue(now: 5, last: -1, interval: 9))
        #expect(!AIProcessRule.isDue(now: 5, last: 1, interval: 9))
        #expect(AIProcessRule.isDue(now: 10, last: 1, interval: 9))
        #expect(AIProcessRule.isDue(now: 1, last: 5, interval: 9))
    }

    @Test func theBudgetJumpsAtBothEdges() {
        #expect(AIProcessRule.budgetMilliseconds(frameSeconds: 1.0 / 60) == 5)
        #expect(AIProcessRule.budgetMilliseconds(frameSeconds: 0.2) == 0.5)
        #expect(abs(AIProcessRule.budgetMilliseconds(frameSeconds: 0.05) - 2.75) < 0.0001)
        #expect(AIProcessRule.budgetMilliseconds(frameSeconds: 0) == 5)
    }

    @Test func aPassOverBudgetGoesOnFromTheSamePlace() {
        var turn = AIProcessTurn<Int>()
        turn.begin(Array(0 ..< 25))
        var updated: [Int] = []
        turn.run(budget: 1, spent: { 2 }, update: { updated.append($0) })
        #expect(updated.count == 10, "the time is read after every 10 actors")
        #expect(turn.isRunning)
        #expect(turn.overBudgetCount == 1)
        turn.run(budget: 1, spent: { 0 }, update: { updated.append($0) })
        #expect(updated == Array(0 ..< 25))
        #expect(!turn.isRunning)
    }
}
