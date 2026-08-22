// `GetCrimeGold` (issue #504, roadmap item 21.5), driven through the real
// evaluator against a synthetic ledger.
//
// The index here is the raw on-disk number 459 — the Creation Kit spells it
// 4555 — from xEdit's condition-function table; see the
// ConditionFunctionsCrime.swift header.
//
// Fixtures are synthetic — never extracted game files (AGENTS.md "Legal & IP
// boundary").

import Foundation
@testable import opensky
import Testing

@MainActor
struct ConditionFunctionsCrimeTests {
    private static let getCrimeGold: UInt16 = 459

    private static let subject = ConditionEvaluatorFixture.key(
        ConditionEvaluatorFixture.subjectFormID
    )

    private static let hold = CrimeFixture.key(CrimeFixture.Factions.hold)

    /// A context whose subject owes the hold `gold`.
    private static func crimeContext(
        gold: Int32 = 40,
        currentCrimeFaction: ReferenceKey? = nil
    ) throws -> ConditionContext {
        var context = try ConditionEvaluatorFixture.populatedContext()
        context.crime = try CrimeConditionResolution(
            factions: CrimeFixture.factionStore(),
            sourcePlugin: CrimeFixture.pluginName,
            currentCrimeFaction: currentCrimeFaction,
            ledgers: [subject: CrimeLedgerState(entries: [
                CrimeLedgerEntry(faction: hold, gold: gold)
            ])]
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
            functionIndex: getCrimeGold,
            comparison,
            value,
            parameter1: parameter1
        ))
        return (outcome, evaluator.tally)
    }

    @Test func itReadsTheBountyOwedToTheNamedFaction() throws {
        let context = try Self.crimeContext()

        // `>= 40` is true and `>= 41` is not, which pins the number rather than
        // just its sign.
        #expect(try Self.evaluate(
            parameter1: CrimeFixture.Factions.hold, context: context, value: 40
        ).outcome == .true)
        #expect(try !(Self.evaluate(
            parameter1: CrimeFixture.Factions.hold, context: context, value: 41
        ).outcome.isTrue))
    }

    /// A faction the player has never offended is owed nothing, which is a real
    /// answer rather than a coverage gap: owing nobody anything is the normal
    /// state every actor in the game starts in.
    @Test func aFactionWithNoRowIsAConclusiveZero() throws {
        let result = try Self.evaluate(
            parameter1: CrimeFixture.Factions.tolerant,
            context: Self.crimeContext(),
            value: 1
        )

        #expect(!result.outcome.isTrue)
        #expect(result.outcome.isConclusive)
        #expect(result.tally.isClean)
    }

    /// `ptFactionNull` is nullable by declaration, and a null parameter asks
    /// about the hold the subject is standing in.
    @Test func aNullParameterMeansTheCurrentCrimeFaction() throws {
        let inHold = try Self.crimeContext(currentCrimeFaction: Self.hold)

        #expect(try Self.evaluate(parameter1: 0, context: inHold, value: 40).outcome == .true)
    }

    /// Outside any hold a null parameter has nothing to ask about, and the
    /// function reports the gap rather than answering zero.
    @Test func aNullParameterOutsideAnyHoldReportsTheGap() throws {
        let result = try Self.evaluate(parameter1: 0, context: Self.crimeContext())

        #expect(!result.outcome.isTrue)
        #expect(result.outcome.failures == [.unavailableCrime])
        #expect(result.tally.unavailableCrime == 1)
    }

    /// A session with no crime data reports the gap, not a player who owes
    /// nothing.
    @Test func aSessionWithNoCrimeDataReportsTheGap() throws {
        var context = try ConditionEvaluatorFixture.populatedContext()
        context.crime = .empty

        let result = try Self.evaluate(
            parameter1: CrimeFixture.Factions.hold, context: context
        )

        #expect(!result.outcome.isTrue)
        #expect(result.outcome.failures == [.unavailableCrime])
    }

    /// A parameter naming a faction no plugin defines is a gap too, because
    /// plugin-relative resolution would otherwise hand back an ordinary key
    /// that reads as "owes this faction nothing".
    @Test func aParameterNamingNoFactionRecordReportsTheGap() throws {
        let result = try Self.evaluate(parameter1: 0xDEAD, context: Self.crimeContext())

        #expect(!result.outcome.isTrue)
        #expect(result.outcome.failures == [.unavailableCrime])
    }

    /// The tally counts the gap in its own bucket, which is what ranks the next
    /// seam to build.
    @Test func theTallyCountsCrimeGapsSeparately() {
        var tally = ConditionTally()
        tally.note(.unavailableCrime)

        #expect(tally.unavailableCrime == 1)
        #expect(tally.failureTotal == 1)
    }
}
