// The transition-condition expression language (issue #330).
//
// The strings asserted here are shapes the probe over the local install found
// in the vanilla player graph, retyped against invented variable names where a
// name would otherwise be copied out of the install. The grammar, not the data,
// is what is under test.

import Foundation
@testable import opensky
import Testing

struct BehaviorConditionExpressionTests {
    /// A store declaring the variables the tests below compare against.
    private func variables() -> BehaviorVariableStore {
        BehaviorVariableStore(
            data: BehaviorFixture.graphData(variables: [
                BehaviorVariableSpec("bReady", .bool, 1),
                BehaviorVariableSpec("bStopped", .bool, 0),
                BehaviorVariableSpec("iHandType", .int32, 7),
                BehaviorVariableSpec("fSpeed", .real, 0.5),
                BehaviorVariableSpec("fLimit", .real, 0.25)
            ])
        )
    }

    private func holds(_ source: String) -> Bool? {
        BehaviorConditionExpression.parse(source)?.evaluate(in: variables())
    }

    @Test func comparesAVariableToALiteral() {
        #expect(holds("iHandType == 7") == true)
        #expect(holds("iHandType != 7") == false)
        #expect(holds("iHandType > 6") == true)
        #expect(holds("iHandType >= 8") == false)
        #expect(holds("iHandType < 8") == true)
        #expect(holds("iHandType <= 6") == false)
    }

    @Test func comparesTwoVariables() {
        #expect(holds("fSpeed >= fLimit") == true)
        #expect(holds("fLimit >= fSpeed") == false)
    }

    @Test func readsALeadingDotLiteral() {
        #expect(holds("fSpeed > .25") == true)
        #expect(holds("fLimit > .25") == false)
    }

    @Test func combinesWithAndOrAndNot() {
        #expect(holds("(bReady == 1) && (iHandType != 7)") == false)
        #expect(holds("(bReady == 1) && (iHandType == 7)") == true)
        #expect(holds("(bReady == 0) || (iHandType == 7)") == true)
        #expect(holds("!bStopped && bReady") == true)
        #expect(holds("!bReady") == false)
    }

    @Test func readsABareVariableAsItsTruth() {
        #expect(holds("bReady") == true)
        #expect(holds("bStopped") == false)
    }

    @Test func conjunctionBindsTighterThanDisjunction() {
        // false && false || true reads as (false && false) || true.
        #expect(holds("bStopped && bStopped || bReady") == true)
        #expect(holds("bReady || bStopped && bStopped") == true)
    }

    @Test func anUnknownVariableMakesEvaluationFail() {
        #expect(holds("bMissing == 1") == nil)
        // Short-circuiting still reports the failure it did not need, because a
        // condition that cannot be fully read must block rather than guess.
        #expect(holds("bStopped && bMissing") == false)
        #expect(holds("bReady || bMissing") == true)
    }

    @Test func refusesTextTheGrammarHasNoPlaceFor() {
        #expect(BehaviorConditionExpression.parse("") == nil)
        #expect(BehaviorConditionExpression.parse("bReady ==") == nil)
        #expect(BehaviorConditionExpression.parse("(bReady == 1") == nil)
        #expect(BehaviorConditionExpression.parse("bReady & bStopped") == nil)
        #expect(BehaviorConditionExpression.parse("bReady + 1") == nil)
        #expect(BehaviorConditionExpression.parse("\"text\"") == nil)
    }

    @Test func theSmoothCurveIsFlatAtBothEnds() {
        #expect(BehaviorBlendCurve.weight(0, curve: BehaviorBlendCurve.smooth) == 0)
        #expect(BehaviorBlendCurve.weight(0.5, curve: BehaviorBlendCurve.smooth) == 0.5)
        #expect(BehaviorBlendCurve.weight(1, curve: BehaviorBlendCurve.smooth) == 1)
        #expect(BehaviorBlendCurve.weight(0.25, curve: BehaviorBlendCurve.smooth) == 0.15625)
        #expect(BehaviorBlendCurve.weight(2, curve: BehaviorBlendCurve.smooth) == 1)
        #expect(BehaviorBlendCurve.weight(-1, curve: BehaviorBlendCurve.smooth) == 0)
    }

    @Test func theLinearCurveIsTheFraction() {
        #expect(BehaviorBlendCurve.weight(0.25, curve: BehaviorBlendCurve.linear) == 0.25)
        #expect(BehaviorBlendCurve.weight(0.75, curve: BehaviorBlendCurve.linear) == 0.75)
    }
}
