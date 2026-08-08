// The five actor condition functions and the combat-target run-on (issue #375,
// roadmap item 15.8), driven through the real evaluator against a synthetic
// fight.
//
// Function indices here are the raw on-disk numbers (Creation Kit number minus
// 4096) — see the ConditionFunctionsActor.swift header for the sources.
//
// Fixtures are synthetic — never extracted game files (AGENTS.md "Legal & IP
// boundary").

import Foundation
@testable import opensky
import Testing

struct ConditionActorFunctionTests {
    private static let getActorValue: UInt16 = 14
    private static let getDead: UInt16 = 46
    private static let isWeaponOut: UInt16 = 263
    private static let getCombatState: UInt16 = 323
    private static let getActorValuePercent: UInt16 = 640
    private static let getIsID: UInt16 = 72

    /// The two placed references `ConditionEvaluatorFixture` builds, standing
    /// in for the player and the bandit fighting them.
    private static let playerKey = ConditionEvaluatorFixture.key(
        ConditionEvaluatorFixture.subjectFormID
    )
    private static let banditKey = ConditionEvaluatorFixture.key(
        ConditionEvaluatorFixture.targetFormID
    )

    /// Health index, the one every actor-value case below reads.
    private static let healthIndex: UInt32 = 24
    /// A real vanilla actor value with no store behind it.
    private static let sneakIndex: UInt32 = 15

    // MARK: - Fixture

    /// A fight: the player half-hurt with a weapon drawn, and a living hostile
    /// bandit at full health with no observed draw state.
    private static func fightContext(
        playerHealth: Float = 50,
        playerDraw: WeaponDrawState? = .drawn,
        banditIsDead: Bool = false,
        banditHostility: ActorHostility = .hostile
    ) throws -> ConditionContext {
        var context = try ConditionEvaluatorFixture.populatedContext()
        context.actors = ActorStateResolution.fight(
            states: [
                playerKey: ActorConditionState(
                    current: ActorValues(health: playerHealth, magicka: 60, stamina: 70),
                    maximums: ActorValues(repeating: 100),
                    weaponDrawState: playerDraw
                ),
                banditKey: ActorConditionState(
                    current: ActorValues(repeating: 100),
                    maximums: ActorValues(repeating: 100),
                    isDead: banditIsDead,
                    hostility: banditHostility
                )
            ],
            playerKey: playerKey,
            // The player is fighting the bandit only while the bandit is both
            // alive and hostile, which is what `CombatLoopState.derive` says.
            playerTarget: banditIsDead || banditHostility != .hostile ? nil : banditKey
        )
        return context
    }

    /// `functionIndex <comparison> value` under `runOn`, evaluated against a
    /// fight. Run-on 0 is the subject, which the fixture binds to the player.
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

    // MARK: - Actor values

    @Test func getActorValueReadsTheCurrentValue() throws {
        let context = try Self.fightContext()
        // Equal to 50, and not equal to the maximum: the function reports the
        // current value rather than the base one.
        #expect(try Self.evaluate(
            Self.getActorValue, 0, 50, parameter1: Self.healthIndex, context: context
        ).outcome == .true)
        #expect(try !Self.evaluate(
            Self.getActorValue, 0, 100, parameter1: Self.healthIndex, context: context
        ).outcome.isTrue)
    }

    @Test func getActorValuePercentIsAFractionOfTheMaximum() throws {
        let context = try Self.fightContext()
        #expect(try Self.evaluate(
            Self.getActorValuePercent, 0, 0.5,
            parameter1: Self.healthIndex, context: context
        ).outcome == .true)
        // Run-on 1 is the target, which is the bandit at full health.
        #expect(try Self.evaluate(
            Self.getActorValuePercent, 0, 1, runOn: 1,
            parameter1: Self.healthIndex, context: context
        ).outcome == .true)
    }

    @Test func anActorValueWithNoStoreIsATalliedParameterMiss() throws {
        let context = try Self.fightContext()
        let result = try Self.evaluate(
            Self.getActorValue, 0, 0, parameter1: Self.sneakIndex, context: context
        )
        #expect(!result.outcome.isTrue)
        #expect(result.outcome.failures == [.unresolvedParameter(Self.getActorValue)])
        #expect(result.tally.unresolvedParameters == [Self.getActorValue: 1])
        #expect(!result.tally.isClean)
    }

    // MARK: - Death, weapon and combat state

    @Test func getDeadReadsTheDeathLatchRatherThanHealth() throws {
        let living = try Self.fightContext()
        #expect(try Self.evaluate(
            Self.getDead, 0, 0, runOn: 1, context: living
        ).outcome == .true)
        let corpse = try Self.fightContext(banditIsDead: true)
        #expect(try Self.evaluate(
            Self.getDead, 0, 1, runOn: 1, context: corpse
        ).outcome == .true)
        // The corpse is at full health, so a health check would disagree —
        // which is exactly why the Creation Kit calls this the reliable one.
        #expect(try Self.evaluate(
            Self.getActorValue, 0, 100, runOn: 1,
            parameter1: Self.healthIndex, context: corpse
        ).outcome == .true)
    }

    @Test func isWeaponOutReportsTwoDrawnAndZeroSheathed() throws {
        let drawn = try Self.fightContext(playerDraw: .drawn)
        #expect(try Self.evaluate(
            Self.isWeaponOut, 0, 2, context: drawn
        ).outcome == .true)
        let sheathed = try Self.fightContext(playerDraw: .sheathed)
        #expect(try Self.evaluate(
            Self.isWeaponOut, 0, 0, context: sheathed
        ).outcome == .true)
    }

    @Test func isWeaponOutOnAnUnobservedActorIsTalliedNotZero() throws {
        let context = try Self.fightContext()
        let result = try Self.evaluate(
            Self.isWeaponOut, 0, 0, runOn: 1, context: context
        )
        #expect(!result.outcome.isTrue)
        #expect(result.outcome.failures == [.unavailableActorState])
        #expect(result.tally.unavailableActorState == 1)
    }

    @Test func getCombatStateIsOneForALivingHostileAndZeroOtherwise() throws {
        let fighting = try Self.fightContext()
        #expect(try Self.evaluate(
            Self.getCombatState, 0, 1, runOn: 1, context: fighting
        ).outcome == .true)
        let calm = try Self.fightContext(banditHostility: .neutral)
        #expect(try Self.evaluate(
            Self.getCombatState, 0, 0, runOn: 1, context: calm
        ).outcome == .true)
        // A hostile corpse is not in combat, matching `CombatLoopState.derive`.
        let corpse = try Self.fightContext(banditIsDead: true)
        #expect(try Self.evaluate(
            Self.getCombatState, 0, 0, runOn: 1, context: corpse
        ).outcome == .true)
    }

    // MARK: - Run-on type 3

    @Test func combatTargetRunOnResolvesBothDirectionsOfTheFight() throws {
        let context = try Self.fightContext()
        // Subject is the player, so run-on 3 is the bandit: full health.
        #expect(try Self.evaluate(
            Self.getActorValuePercent, 0, 1, runOn: 3,
            parameter1: Self.healthIndex, context: context
        ).outcome == .true)
        // `GetIsID` under run-on 3 confirms it is the bandit's *placement* that
        // was resolved, not merely some actor state: the base form matches.
        var evaluator = ConditionEvaluator(context: context)
        let outcome = try evaluator.evaluate(ConditionEvaluatorFixture.condition(
            comparisonValue: Float(1).bitPattern,
            functionIndex: Self.getIsID,
            parameter1: ConditionEvaluatorFixture.targetBase,
            runOn: 3
        ))
        #expect(outcome == .true)
        #expect(evaluator.tally.isClean)
    }

    @Test func combatTargetRunOnSwapsWithTheSubjectTargetFlag() throws {
        let context = try Self.fightContext()
        // With the swap flag the subject side reads the *target's* fight, and
        // the bandit is fighting the player, who is at half health.
        let condition = try ConditionEvaluatorFixture.condition(
            flags: 0x10,
            comparisonValue: Float(0.5).bitPattern,
            functionIndex: Self.getActorValuePercent,
            parameter1: Self.healthIndex,
            runOn: 3
        )
        var evaluator = ConditionEvaluator(context: context)
        #expect(evaluator.evaluate(condition) == .true)
    }

    @Test func combatTargetRunOnWithNoFightIsATalliedUnresolvedReference() throws {
        let calm = try Self.fightContext(banditHostility: .neutral)
        let result = try Self.evaluate(
            Self.getDead, 0, 0, runOn: 3, context: calm
        )
        #expect(!result.outcome.isTrue)
        #expect(result.outcome.failures == [.unresolvedReference(.combatTarget)])
        // The run-on itself is supported now, so nothing lands in the
        // unsupported bucket that used to hold every combat-target condition.
        #expect(result.tally.unsupportedRunOnTotal == 0)
        #expect(result.tally.rankedUnresolvedReferences.map(\.name) == ["combatTarget"])
    }

    // MARK: - Identity without a record

    @Test func anActorWithNoPluginRecordStillAnswers() throws {
        // The player has a `ReferenceKey` and no REFR, so a function that asks
        // for the decoded record cannot answer for it and one that asks only
        // for identity can. That split is the whole reason `referenceKey()`
        // exists beside `reference()`.
        var context = try ConditionEvaluatorFixture.populatedContext()
        context.subject = .player
        context.actors = ActorStateResolution(states: [
            .player: ActorConditionState(
                current: ActorValues(repeating: 40),
                maximums: ActorValues(repeating: 100)
            )
        ])
        #expect(try Self.evaluate(
            Self.getActorValuePercent, 0, 0.4,
            parameter1: Self.healthIndex, context: context
        ).outcome == .true)
        // `GetIsID` under the same run-on does need the record, and says so.
        let identity = try Self.evaluate(
            Self.getIsID, 0, 1,
            parameter1: ConditionEvaluatorFixture.subjectBase, context: context
        )
        #expect(identity.outcome.failures == [.unresolvedReference(.subject)])
    }

    // MARK: - No actor seam at all

    @Test func anEmptyActorSeamTalliesRatherThanAnswering() throws {
        let context = try ConditionEvaluatorFixture.populatedContext()
        #expect(context.actors.isEmpty)
        let result = try Self.evaluate(Self.getDead, 0, 0, context: context)
        #expect(!result.outcome.isTrue)
        #expect(result.outcome.failures == [.unavailableActorState])
        #expect(result.tally.unavailableActorState == 1)
        #expect(result.tally.failureTotal == 1)
    }
}
