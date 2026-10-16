// The `hkbEvaluateExpressionModifier` statement parser and evaluator, over
// statements shaped like the vanilla ones. Values are invented.

import Foundation
@testable import OpenSkyBehavior
import Testing

struct BehaviorExpressionTests {
    private let values: [String: Float] = ["TurnDelta": -45, "iCombatStance": 1, "1stPRot": 2]

    private func evaluate(_ source: String) -> Float? {
        guard
            case let .assignment(_, expression) = BehaviorExpressionStatement
                .parse("x = \(source)")
        else { return nil }
        return expression.evaluate { values[$0] }
    }

    @Test func parsesBothStatementForms() {
        #expect(BehaviorExpressionStatement.parse("speed = TurnDelta * 2")
            == .assignment(
                variable: "speed",
                value: .binary("*", .variable("TurnDelta"), .number(2))
            ))
        #expect(BehaviorExpressionStatement.parse("weaponDraw if (iCombatStance == 1)")
            == .event(name: "weaponDraw", condition: .binary(
                "==", .variable("iCombatStance"), .number(1)
            )))
        #expect(BehaviorExpressionStatement.parse("just words") == nil)
        #expect(BehaviorExpressionStatement.parse("x = (1 + ") == nil)
    }

    @Test func evaluatesWithPrecedenceAndFunctions() {
        #expect(evaluate("1 + 2 * 3") == 7)
        #expect(evaluate("(1 + 2) * 3") == 9)
        #expect(evaluate("fabs(TurnDelta / 90)") == 0.5)
        #expect(evaluate("-TurnDelta > 40 && !0") == 1)
        #expect(evaluate("cond(iCombatStance == 1, 10, 20)") == 10)
        #expect(evaluate("clamp(1stPRot, 0, 1)") == 1)
        #expect(evaluate("7 % 4 + max(1, 3)") == 6)
        #expect(evaluate("1 / 0") == 0)
    }

    @Test func anUnknownNameDoesNotEvaluate() {
        #expect(evaluate("missing + 1") == nil)
        #expect(evaluate("nosuchfunction(1)") == nil)
    }

    @Test func randomSequenceIsSeededAndInRange() {
        var first = BehaviorRandom()
        var second = BehaviorRandom()
        let draws = (0 ..< 20).map { _ in first.next(in: 2 ... 5) }
        #expect(draws == (0 ..< 20).map { _ in second.next(in: 2 ... 5) })
        #expect(draws.allSatisfy { (2 ... 5).contains($0) })
    }

    @Test func variableRolesSplitEngineAndGraphVariables() {
        #expect(BehaviorVariableRoles.isEngineFacing("speed", uses: []))
        #expect(!BehaviorVariableRoles.isEngineFacing("myLocalBlend", uses: []))
        #expect(BehaviorVariableRoles.isEngineFacing(
            "lookTarget", uses: ["BSLookAtModifier.targetLocation"]
        ))
        #expect(BehaviorVariableRoles.isGraphWritten(
            uses: ["BSInterpValueModifier.result"], assignedUse: "expression assignment"
        ))
        #expect(!BehaviorVariableRoles.isGraphWritten(
            uses: ["hkbBlenderGenerator.blendParameter"], assignedUse: "expression assignment"
        ))
    }
}
