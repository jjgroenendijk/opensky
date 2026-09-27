// `HasPerk` (issue #497, roadmap item 20.4), driven through the real evaluator
// against a synthetic perk set.
//
// The index here is the raw on-disk number 448 — the Creation Kit spells it
// 4544 — from xEdit's condition-function table; see the
// ConditionFunctionsPerk.swift header.
//
// Fixtures are synthetic — never extracted game files (AGENTS.md "Legal & IP
// boundary").

import Foundation
@testable import opensky
import Testing

@MainActor
struct ConditionPerkFunctionTests {
    private static let hasPerk: UInt16 = 448

    private static let subject = ConditionEvaluatorFixture.key(
        ConditionEvaluatorFixture.subjectFormID
    )

    /// A context whose subject owns the blocking perk and nothing else.
    private static func perkContext(owning: [UInt32] = [PerkRuntimeFixture.Perk.blocking]) throws
        -> ConditionContext
    {
        var context = try ConditionEvaluatorFixture.populatedContext()
        context.perks = try PerkConditionResolution(
            store: PerkRuntimeFixture.perkStore(index: PerkRuntimeFixture.index()),
            sourcePlugin: PerkRuntimeFixture.pluginName,
            owned: [subject: Set(owning.map(PerkRuntimeFixture.key))]
        )
        return context
    }

    private static func evaluate(
        parameter1: UInt32,
        context: ConditionContext,
        comparison: UInt8 = 0,
        value: Float = 1
    ) throws -> (outcome: ConditionOutcome, tally: ConditionTally) {
        var evaluator = ConditionEvaluator(context: context)
        let outcome = try evaluator.evaluate(ConditionEvaluatorFixture.comparing(
            functionIndex: hasPerk,
            comparison,
            value,
            parameter1: parameter1
        ))
        return (outcome, evaluator.tally)
    }

    @Test func hasPerkAnswersFromTheOwnedSet() throws {
        let context = try Self.perkContext()

        #expect(try Self.evaluate(
            parameter1: PerkRuntimeFixture.Perk.blocking, context: context
        ).outcome == .true)
    }

    /// A perk the load order carries and the actor has not taken is a real 0
    /// rather than a coverage gap, which is what a rank chain's own
    /// `HasPerk <next rank> == 0` switch relies on.
    @Test func aPerkTheActorHasNotTakenIsAConclusiveFalse() throws {
        let context = try Self.perkContext()

        let result = try Self.evaluate(
            parameter1: PerkRuntimeFixture.Perk.damageRank2, context: context
        )

        #expect(!result.outcome.isTrue)
        #expect(result.outcome.isConclusive)
        #expect(result.tally.isClean)
        // The same condition compared against 0, which is how the records
        // author the switch, is true.
        #expect(try Self.evaluate(
            parameter1: PerkRuntimeFixture.Perk.damageRank2, context: context, value: 0
        ).outcome == .true)
    }

    /// An actor the seam carries no entry for owns nothing, which is the normal
    /// state every actor in the game starts in.
    @Test func anActorWithNoPerkComponentOwnsNothing() throws {
        let context = try Self.perkContext(owning: [])

        let result = try Self.evaluate(
            parameter1: PerkRuntimeFixture.Perk.blocking, context: context
        )

        #expect(!result.outcome.isTrue)
        #expect(result.tally.isClean)
    }

    /// A session with no perk data is a reason-tagged false rather than an
    /// actor who has taken nothing.
    @Test func aSessionWithNoPerkDataReportsTheGap() throws {
        let context = try ConditionEvaluatorFixture.populatedContext()

        let result = try Self.evaluate(
            parameter1: PerkRuntimeFixture.Perk.blocking, context: context
        )

        #expect(!result.outcome.isTrue)
        #expect(result.outcome.failures == [.unavailablePerks])
        #expect(result.tally.unavailablePerks == 1)
    }

    /// A parameter no loaded plugin resolves is the same gap: "this engine has
    /// no such perk" is not "this actor does not have it".
    @Test func aParameterNoPluginCarriesReportsTheGap() throws {
        let context = try Self.perkContext()

        let result = try Self.evaluate(parameter1: 0x0BAD, context: context)

        #expect(result.outcome.failures == [.unavailablePerks])
    }
}
