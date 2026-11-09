// ShouldAttackKill through the real evaluator: the kill-move idles leave its target
// empty, so it reads the subject's own attack.

@testable import OpenSkyConditions
import OpenSkyFeaturesTesting
import OpenSkyFormatsESM
import OpenSkyWorldConditions
import Testing

struct ConditionAttackFunctionTests {
    private static let shouldAttackKill: UInt16 = 678
    private static let subject = ConditionEvaluatorFixture
        .key(ConditionEvaluatorFixture.subjectFormID)
    private static let target = ConditionEvaluatorFixture
        .key(ConditionEvaluatorFixture.targetFormID)

    private static func outcome(
        equals value: Float, kills: Bool?, parameter1: UInt32 = 0
    ) throws -> ConditionOutcome {
        var context = try ConditionEvaluatorFixture.populatedContext()
        if let kills {
            context.attackKills = AttackKillResolution(attacks: [
                AttackKillResolution.Attack(attacker: subject, target: target, kills: kills)
            ])
        }
        var evaluator = ConditionEvaluator(context: context.using(.standard))
        return try evaluator.evaluate(ConditionEvaluatorFixture.comparing(
            functionIndex: shouldAttackKill, 0, value, parameter1: parameter1
        ))
    }

    @Test func anEmptyTargetReadsTheSubjectsAttack() throws {
        #expect(try Self.outcome(equals: 1, kills: true) == .true)
        #expect(try Self.outcome(equals: 0, kills: false) == .true)
    }

    @Test func aNamedTargetMustMatchTheAttack() throws {
        let named = ConditionEvaluatorFixture.targetFormID
        #expect(try Self.outcome(equals: 1, kills: true, parameter1: named) == .true)
        let other = ConditionEvaluatorFixture.subjectFormID
        let outcome = try Self.outcome(equals: 1, kills: true, parameter1: other)
        #expect(outcome.failures == [.unavailableData(.attack)])
    }

    @Test func noWeighedAttackFailsWithAReason() throws {
        let outcome = try Self.outcome(equals: 0, kills: nil)
        #expect(outcome.failures == [.unavailableData(.attack)])
    }
}
