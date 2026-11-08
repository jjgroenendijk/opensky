// The crime-encounter functions read `CrimeSituation`: victims, trespass, alarm,
// arrest, jail days, guards, and ownership. No situation fails with a reason.

import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
@testable import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
import OpenSkyWorldConditions
import Testing

@MainActor
struct ConditionCrimeSituationFunctionTests {
    private static let subject = ConditionEvaluatorFixture
        .key(ConditionEvaluatorFixture.subjectFormID)
    private static let hold = CrimeFixture.key(CrimeFixture.Factions.hold)
    private static let guardFaction = CrimeFixture.key(CrimeFixture.Factions.guards)

    private static func outcome(
        _ function: UInt16, equals value: Float, situation: CrimeSituation?,
        profile: ActorSocialProfile? = nil, parameter1: UInt32 = 0
    ) throws -> ConditionOutcome {
        var context = try ConditionEvaluatorFixture.populatedContext()
        let store = try CrimeFixture.factionStore()
        context.crime = CrimeConditionResolution(
            factions: store, sourcePlugin: CrimeFixture.pluginName, situation: situation
        )
        context.factions = FactionConditionResolution(
            factions: store, sourcePlugin: CrimeFixture.pluginName,
            profiles: profile.map { [subject: $0] } ?? [:]
        )
        var evaluator = ConditionEvaluator(context: context)
        return try evaluator.evaluate(ConditionEvaluatorFixture.comparing(
            functionIndex: function, 0, value, parameter1: parameter1
        ))
    }

    @Test func membershipFunctionsReadTheSituation() throws {
        let marked = CrimeSituation(
            victims: [Self.subject], alarmed: [Self.subject], arrestingGuard: Self.subject
        )
        for function: UInt16 in [314, 61, 657] {
            #expect(try Self.outcome(function, equals: 1, situation: marked) == .true)
            #expect(try Self.outcome(function, equals: 0, situation: CrimeSituation()) == .true)
        }
        #expect(try Self.outcome(145, equals: 0, situation: marked) == .true)
        // Only the player is ever arrested.
        #expect(try Self.outcome(656, equals: 0, situation: marked) == .true)
    }

    @Test func jailDaysAndTrespassWarningAreNumbers() throws {
        let served = CrimeSituation(lastSentenceDays: 3)
        #expect(try Self.outcome(499, equals: 3, situation: served) == .true)
        #expect(try Self.outcome(144, equals: 0, situation: served) == .true)
        var warned = served
        warned.trespassWarnings = [Self.subject: 2]
        #expect(try Self.outcome(144, equals: 2, situation: warned) == .true)
    }

    @Test func aGuardPolicesItsCrimeFaction() throws {
        let guardProfile = ActorSocialProfile(
            key: Self.subject,
            memberships: ActorFactionState(memberships: [
                ActorFactionMembership(faction: Self.guardFaction, rank: 0)
            ]),
            crimeFaction: Self.hold
        )
        let situation = CrimeSituation(
            guardFaction: Self.guardFaction, payableFactions: [Self.hold]
        )
        #expect(try Self
            .outcome(125, equals: 1, situation: situation, profile: guardProfile) == .true)
        #expect(try Self
            .outcome(497, equals: 1, situation: situation, profile: guardProfile) == .true)
        let civilian = ActorSocialProfile(key: Self.subject, crimeFaction: Self.hold)
        #expect(try Self.outcome(125, equals: 0, situation: situation, profile: civilian) == .true)
        #expect(try Self.outcome(497, equals: 0, situation: CrimeSituation(
            guardFaction: Self.guardFaction
        ), profile: guardProfile) == .true)
    }

    @Test func isOwnerComparesTheResolvedOwner() throws {
        let owned = CrimeSituation(owners: [Self.subject: .faction(Self.hold, requiredRank: 0)])
        #expect(try Self.outcome(
            278, equals: 1, situation: owned, parameter1: CrimeFixture.Factions.hold
        ) == .true)
        #expect(try Self.outcome(
            278, equals: 0, situation: owned, parameter1: CrimeFixture.Factions.tolerant
        ) == .true)
    }

    @Test func noSituationFailsWithAReason() throws {
        #expect(try Self.outcome(314, equals: 0, situation: nil).failures == [.unavailableCrime])
    }
}
