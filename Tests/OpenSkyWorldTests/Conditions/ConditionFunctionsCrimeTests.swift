// `GetCrimeGold` through the real evaluator. Raw index 459 (Creation Kit 4555);
// see the ConditionFunctionsCrime.swift header.

import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyCrimeInterface
@testable import OpenSkyCrimeTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyWorld
import OpenSkyWorldTesting
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
        violentGold: Int32 = 0,
        currentCrimeFaction: ReferenceKey? = nil
    ) throws -> ConditionContext {
        var context = try ConditionEvaluatorFixture.populatedContext()
        context.crime = try CrimeConditionResolution(
            factions: CrimeFixture.factionStore(),
            sourcePlugin: CrimeFixture.pluginName,
            currentCrimeFaction: currentCrimeFaction,
            ledgers: [subject: CrimeLedgerState(entries: [
                CrimeLedgerEntry(faction: hold, nonViolentGold: gold, violentGold: violentGold)
            ])]
        )
        return context
    }

    private static func evaluate(
        parameter1: UInt32,
        context: ConditionContext,
        comparison: UInt8 = 0,
        value: Float = 1,
        function: UInt16 = getCrimeGold
    ) throws -> (outcome: ConditionOutcome, tally: ConditionTally) {
        var evaluator = ConditionEvaluator(context: context)
        let outcome = try evaluator.evaluate(ConditionEvaluatorFixture.comparing(
            functionIndex: function,
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

    /// `GetCrimeGoldViolent` (375) and `GetCrimeGoldNonviolent` (376) each
    /// read one half, and `GetCrimeGold` reads their sum.
    @Test func theViolentAndNonviolentFunctionsReadOneHalfEach() throws {
        let context = try Self.crimeContext(gold: 25, violentGold: 40)
        let hold = CrimeFixture.Factions.hold

        for (function, owed) in [(UInt16(375), Float(40)), (376, 25), (459, 65)] {
            // Equal to `owed` and not to `owed + 1` pins the exact number.
            #expect(try Self.evaluate(
                parameter1: hold, context: context, value: owed, function: function
            ).outcome == .true)
            #expect(try !(Self.evaluate(
                parameter1: hold, context: context, value: owed + 1, function: function
            ).outcome.isTrue))
        }
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
