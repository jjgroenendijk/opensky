// `GetLevel` and `GetBaseActorValue` (issue #499, roadmap item 20.6), driven
// through the real evaluator against a synthetic actor pair.
//
// Function indices here are the raw on-disk numbers (Creation Kit number minus
// 4096), from xEdit dev-4.1.6 `Core/wbDefinitionsTES5.pas`:
//
//   (Index:  80; Name: 'GetLevel')
//   (Index: 277; Name: 'GetBaseActorValue'; ParamType1: ptActorValue)
//
// The pair is what every vanilla perk requirement is written with: `Armsman20`
// reads `GetBaseActorValue One-Handed >= 20`, measured on this machine
// 2026-08-20. Fixtures are synthetic — never extracted game files (AGENTS.md
// "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

struct ConditionLevelFunctionTests {
    private static let getLevel: UInt16 = 80
    private static let getBaseActorValue: UInt16 = 277
    private static let getActorValue: UInt16 = 14

    private static let greaterThanOrEqual: UInt8 = 3
    private static let equal: UInt8 = 0

    private static let playerKey = ConditionEvaluatorFixture.key(
        ConditionEvaluatorFixture.subjectFormID
    )
    private static let banditKey = ConditionEvaluatorFixture.key(
        ConditionEvaluatorFixture.targetFormID
    )

    private static let oneHandedIndex = UInt32(
        bitPattern: ActorValueIdentity.firstSkillIndex
    )
    private static let unknownIndex: UInt32 = 164

    /// A level-20 player whose One-Handed base is 30 but whose *current*
    /// One-Handed is fortified to 80, beside a level-7 bandit.
    private static func context(
        playerLevel: Int = 20,
        oneHandedBase: Float = 30,
        fortify: Float = 50
    ) throws -> ConditionContext {
        var context = try ConditionEvaluatorFixture.populatedContext()
        context.actors = ActorStateResolution(states: [
            playerKey: ActorConditionState(
                current: ActorValues(repeating: 100),
                maximums: ActorValues(repeating: 100),
                general: [
                    ActorValueIdentity.firstSkillIndex: ActorValueEntry(
                        base: oneHandedBase, permanent: fortify
                    )
                ],
                isPlayer: true,
                level: playerLevel
            ),
            banditKey: ActorConditionState(
                current: ActorValues(repeating: 100),
                maximums: ActorValues(repeating: 100),
                level: 7
            )
        ])
        return context
    }

    private static func evaluate(
        _ functionIndex: UInt16,
        _ comparison: UInt8,
        _ value: Float,
        runOn: UInt32 = 0,
        parameter1: UInt32 = 0,
        context: ConditionContext
    ) throws -> (outcome: ConditionOutcome, tally: ConditionTally) {
        var evaluator = ConditionEvaluator(context: context)
        let outcome = try evaluator.evaluate(ConditionEvaluatorFixture.comparing(
            functionIndex: functionIndex,
            comparison,
            value,
            runOn: runOn,
            parameter1: parameter1
        ))
        return (outcome, evaluator.tally)
    }

    @Test func getLevelReadsTheSubjectsLevel() throws {
        let context = try Self.context()

        #expect(try Self.evaluate(
            Self.getLevel, Self.equal, 20, context: context
        ).outcome == .true)
        // Run-on 1 is the target, which the fixture binds to the bandit.
        #expect(try Self.evaluate(
            Self.getLevel, Self.equal, 7, runOn: 1, context: context
        ).outcome == .true)
    }

    /// An actor the seam carries no state for is a counted miss rather than a
    /// level of zero that a condition would then act on.
    @Test func getLevelOnAnUnknownActorIsACountedMiss() throws {
        var context = try Self.context()
        context.actors = .empty

        let (outcome, tally) = try Self.evaluate(
            Self.getLevel, Self.equal, 1, context: context
        )

        #expect(!outcome.isTrue)
        #expect(outcome.failures == [.unavailableActorState])
        #expect(tally.unavailableActorState == 1)
    }

    /// The whole point of the base read: a fortified skill is not a trained
    /// one, so a perk requirement stated with `GetBaseActorValue` is something
    /// a potion cannot buy.
    @Test func getBaseActorValueIgnoresAFortifyModifier() throws {
        let context = try Self.context()

        #expect(try Self.evaluate(
            Self.getBaseActorValue,
            Self.greaterThanOrEqual,
            30,
            parameter1: Self.oneHandedIndex,
            context: context
        ).outcome == .true)
        // The vanilla `Armsman20` requirement, which this player does not meet
        // on its base and would meet on its fortified total.
        #expect(try Self.evaluate(
            Self.getBaseActorValue,
            Self.greaterThanOrEqual,
            50,
            parameter1: Self.oneHandedIndex,
            context: context
        ).outcome == .false)
        #expect(try Self.evaluate(
            Self.getActorValue,
            Self.greaterThanOrEqual,
            50,
            parameter1: Self.oneHandedIndex,
            context: context
        ).outcome == .true)
    }

    /// A skill nothing has touched reads its documented floor rather than
    /// tallying a miss, because item 19.5 stores the whole table.
    @Test func anUntouchedSkillReadsItsFloor() throws {
        var context = try Self.context()
        context.actors = ActorStateResolution(states: [
            Self.playerKey: ActorConditionState(
                current: ActorValues(repeating: 100),
                maximums: ActorValues(repeating: 100),
                isPlayer: true
            )
        ])

        #expect(try Self.evaluate(
            Self.getBaseActorValue,
            Self.equal,
            ActorValueIdentity.skillFloor,
            parameter1: Self.oneHandedIndex,
            context: context
        ).outcome == .true)
    }

    /// A parameter naming no vanilla actor value is a counted parameter miss,
    /// keyed by this function rather than by `GetActorValue`.
    @Test func anIndexOutsideTheTableIsACountedParameterMiss() throws {
        let context = try Self.context()

        let (outcome, tally) = try Self.evaluate(
            Self.getBaseActorValue,
            Self.equal,
            0,
            parameter1: Self.unknownIndex,
            context: context
        )

        #expect(!outcome.isTrue)
        #expect(outcome.failures == [.unresolvedParameter(Self.getBaseActorValue)])
        #expect(tally.unresolvedParameters[Self.getBaseActorValue] == 1)
    }
}
