// The relationship-record and hostility condition functions over a synthetic load
// order: association types, family, parent, shared crime faction, and attack.

import Foundation
@testable import OpenSkyConditions
import OpenSkyFactionsFixtures
@testable import OpenSkyFactionsInterface
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
import Testing

struct ConditionRelationshipRecordTests {
    private typealias Fixture = HostilityFixture

    private static let subject = ConditionEvaluatorFixture
        .key(ConditionEvaluatorFixture.subjectFormID)
    private static let target = ConditionEvaluatorFixture
        .key(ConditionEvaluatorFixture.targetFormID)
    private static let parent = Fixture.Actors.cityGuard
    private static let child = Fixture.Actors.townsfolk

    private static func evaluate(
        _ function: UInt16, equals value: Float,
        parameter1: UInt32 = ConditionEvaluatorFixture.targetFormID, parameter2: UInt32 = 0,
        pairs: [Fixture.Pair] = [], subjectBase: UInt32 = parent, targetBase: UInt32 = child,
        crimeFactions: (ReferenceKey?, ReferenceKey?) = (nil, nil),
        playerMemberships: [(faction: UInt32, rank: Int8)] = []
    ) throws -> ConditionOutcome {
        var context = try ConditionEvaluatorFixture.populatedContext()
        var subjectProfile = Fixture.profile(actor: subjectBase, key: subject)
        subjectProfile.crimeFaction = crimeFactions.0
        var targetProfile = Fixture.profile(actor: targetBase, key: target)
        targetProfile.crimeFaction = crimeFactions.1
        context.factions = try FactionConditionResolution(
            factions: Fixture.factionStore(),
            sourcePlugin: Fixture.pluginName,
            derivation: Fixture.derivation(pairs: pairs),
            profiles: [
                subject: subjectProfile, target: targetProfile,
                .player: Fixture.player(memberships: playerMemberships)
            ]
        )
        var registry = ConditionFunctionRegistry()
        ConditionFunctions.installFaction(&registry)
        var evaluator = ConditionEvaluator(context: context, registry: registry)
        return try evaluator.evaluate(ConditionEvaluatorFixture.condition(
            comparisonValue: value.bitPattern, functionIndex: function,
            parameter1: parameter1, parameter2: parameter2
        ))
    }

    private static let family = [Fixture.Pair(
        parent, child, .friend, association: Fixture.Associations.parentChild
    )]

    @Test func associationTypeMatchesTheRecord() throws {
        let wanted = Fixture.Associations.parentChild
        #expect(try Self.evaluate(258, equals: 1, parameter2: wanted, pairs: Self.family) == .true)
        #expect(try Self.evaluate(
            258, equals: 0, parameter2: Fixture.Associations.courier, pairs: Self.family
        ) == .true)
    }

    @Test func familyAndParentFollowTheAssociationType() throws {
        #expect(try Self.evaluate(259, equals: 1, pairs: Self.family) == .true)
        #expect(try Self.evaluate(261, equals: 1, pairs: Self.family) == .true)
        // The child is not the parent of the parent.
        #expect(try Self.evaluate(
            261, equals: 0, pairs: Self.family, subjectBase: Self.child, targetBase: Self.parent
        ) == .true)
        let courier = [Fixture.Pair(
            Self.parent, Self.child, .friend, association: Fixture.Associations.courier
        )]
        #expect(try Self.evaluate(259, equals: 0, pairs: courier) == .true)
    }

    @Test func lowestRankIsTheWorstRecord() throws {
        let pairs = [
            Fixture.Pair(Self.parent, Self.child, .friend),
            Fixture.Pair(Self.parent, Fixture.Actors.bandit, .enemy)
        ]
        #expect(try Self.evaluate(616, equals: -3, pairs: pairs) == .true)
        #expect(try Self.evaluate(616, equals: 0) == .true)
    }

    @Test func sharedCrimeFactionNeedsTheSameFaction() throws {
        let hold = Fixture.key(Fixture.Factions.town)
        #expect(try Self.evaluate(652, equals: 1, crimeFactions: (hold, hold)) == .true)
        #expect(try Self.evaluate(652, equals: 0, crimeFactions: (hold, nil)) == .true)
    }

    @Test func pcInFactionReadsThePlayer() throws {
        #expect(try Self.evaluate(
            132, equals: 1, parameter1: Fixture.Factions.town,
            playerMemberships: [(Fixture.Factions.town, 0)]
        ) == .true)
        #expect(try Self.evaluate(132, equals: 0, parameter1: Fixture.Factions.town) == .true)
    }

    @Test func friendStateNeedsAFriendlyRankToThePlayer() throws {
        #expect(try Self.evaluate(638, equals: 0) == .true)
    }
}
