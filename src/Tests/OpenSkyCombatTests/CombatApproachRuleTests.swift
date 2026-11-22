// The pace of a fighter's approach by distance band (docs/engine/combat-approach.md).

import OpenSkyCombatInterface
import Testing

struct CombatApproachRuleTests {
    @Test func theStyleDifferencePicksTheRadii() {
        #expect(CombatApproachRule.radiusLevel(offensive: 1, defensive: 0) == 0)
        #expect(CombatApproachRule.radiusLevel(offensive: 0.5, defensive: 0.5) == 0.5)
        #expect(CombatApproachRule.radiusLevel(offensive: 0, defensive: 1) == 1)
        #expect(CombatApproachRule.radiusLevel(offensive: 0, defensive: 5) == 1)
        #expect(CombatApproachRule.radiusLevel(offensive: .nan, defensive: 0) == 0.5)
    }

    @Test func aFighterRunsBeyondTheOuterRadiusAndSlowsNearTheInnerOne() {
        func pace(_ distance: Float) -> CombatPace {
            CombatApproachRule.pace(
                distance: distance, inner: 50, outer: 200, slowdownDistance: 96
            )
        }
        #expect(pace(300) == .run)
        #expect(pace(180) == .fastWalk)
        #expect(pace(146) == .fastWalk)
        #expect(abs(pace(98).level - 1.165) < 0.001)
        #expect(pace(50) == .walk)
        #expect(pace(10) == .walk)
        let noBand = CombatApproachRule.pace(
            distance: 60, inner: 50, outer: 200, slowdownDistance: 0
        )
        #expect(noBand == .fastWalk)
    }

    @Test func aPaceStaysBetweenWalkAndRun() {
        #expect(CombatPace(level: 5) == .run)
        #expect(CombatPace(level: 0.2) == .walk)
        #expect(CombatPace(level: .nan) == .walk)
        #expect(CombatPace.run.runs && !CombatPace.fastWalk.runs)
        #expect(abs(CombatPace.fastWalk.walkRunBlend - 0.33) < 0.001)
        #expect(CombatPace.walk.walkRunBlend == 0)
    }
}
