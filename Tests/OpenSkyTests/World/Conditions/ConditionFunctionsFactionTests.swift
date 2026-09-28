// The six faction and relationship condition functions (issue #508, roadmap
// item 21.4), driven through the real evaluator against synthetic stores.
//
// Indices here are the raw on-disk numbers from xEdit's condition-function
// table; the Creation Kit spells each 4096 higher. See the
// ConditionFunctionsFaction.swift header for the table rows themselves.
//
// Fixtures are synthetic — never extracted game files (AGENTS.md "Legal & IP
// boundary").

import Foundation
@testable import OpenSkyEngine
@testable import OpenSkyFormatsESM
import Testing

@MainActor
struct ConditionFunctionsFactionTests {
    private typealias Fixture = HostilityFixture

    private enum Index {
        static let rankDifference: UInt16 = 60
        static let inFaction: UInt16 = 71
        static let rank: UInt16 = 73
        static let relationshipRank: UInt16 = 403
        static let factionRelation: UInt16 = 449
        static let hostileToActor: UInt16 = 719
    }

    private static let subject = ConditionEvaluatorFixture.key(
        ConditionEvaluatorFixture.subjectFormID
    )
    private static let target = ConditionEvaluatorFixture.key(
        ConditionEvaluatorFixture.targetFormID
    )

    // MARK: - Memberships

    @Test func getInFactionAnswersOneForAMember() throws {
        let context = try Self.context(
            subjectMemberships: [(Fixture.Factions.guards, 2)]
        )

        #expect(try Self.evaluate(
            Index.inFaction, parameter1: Fixture.Factions.guards, context: context
        ).outcome == .true)
        #expect(try Self.evaluate(
            Index.inFaction, parameter1: Fixture.Factions.bandit, context: context
        ).outcome == .false)
    }

    /// The parameter has to name a FACT this load order actually carries. A
    /// FormID nothing defines is a gap rather than "not a member", because the
    /// two are different answers and only one is about the actor.
    @Test func aFactionNoPluginDefinesIsAGapRatherThanANonMember() throws {
        let result = try Self.evaluate(
            Index.inFaction,
            parameter1: 0x0000_BEEF,
            context: Self.context(subjectMemberships: [(Fixture.Factions.guards, 2)])
        )

        #expect(!result.outcome.isTrue)
        #expect(result.outcome.failures == [.unavailableFactions])
        #expect(result.tally.unavailableFactions == 1)
    }

    /// "Returns the actor's rank in the faction."
    /// (<https://ck.uesp.net/wiki/GetFactionRank>)
    @Test func getFactionRankReadsTheStoredRank() throws {
        let context = try Self.context(
            subjectMemberships: [(Fixture.Factions.guards, 3)]
        )

        // `== 3` true and `== 4` false pins the number rather than its sign.
        #expect(try Self.evaluate(
            Index.rank, parameter1: Fixture.Factions.guards, context: context, value: 3
        ).outcome == .true)
        #expect(try !Self.evaluate(
            Index.rank, parameter1: Fixture.Factions.guards, context: context, value: 4
        ).outcome.isTrue)
    }

    /// "If the actor isn't in the faction ... this returns -1."
    /// (<https://ck.uesp.net/wiki/GetFactionRank>) Note that this is *not* the
    /// -2 the Papyrus native of the same name answers with.
    @Test func getFactionRankAnswersMinusOneForANonMember() throws {
        let result = try Self.evaluate(
            Index.rank,
            parameter1: Fixture.Factions.bandit,
            context: Self.context(subjectMemberships: [(Fixture.Factions.guards, 3)]),
            comparison: 0, // equal to
            value: -1
        )

        #expect(result.outcome == .true)
        #expect(result.tally.isClean)
    }

    /// A rank of 0 is a real rank vanilla authors freely, so a member at rank 0
    /// must not read as the -1 a non-member gets.
    @Test func rankZeroIsNotTheNonMemberValue() throws {
        let context = try Self.context(
            subjectMemberships: [(Fixture.Factions.guards, 0)]
        )

        #expect(try Self.evaluate(
            Index.rank,
            parameter1: Fixture.Factions.guards,
            context: context,
            comparison: 0,
            value: 0
        ).outcome == .true)
    }

    /// "Returns the difference in rank between the current actor and target
    /// actor in the specified faction."
    /// (<https://ck.uesp.net/wiki/GetFactionRankDifference>)
    @Test func rankDifferenceSubtractsTheParameterActorFromTheRunOn() throws {
        let context = try Self.context(
            subjectMemberships: [(Fixture.Factions.guards, 4)],
            targetMemberships: [(Fixture.Factions.guards, 1)]
        )

        #expect(try Self.evaluateRankDifference(context: context, value: 3).outcome == .true)
        #expect(try !Self.evaluateRankDifference(context: context, value: 4).outcome.isTrue)
    }

    /// A non-member on either side counts as the same -1 `GetFactionRank`
    /// reports, so an outsider is three ranks below a rank-2 member.
    @Test func rankDifferenceTreatsANonMemberAsMinusOne() throws {
        let context = try Self.context(
            subjectMemberships: [(Fixture.Factions.guards, 2)]
        )

        #expect(try Self.evaluateRankDifference(
            context: context, comparison: 0, value: 3
        ).outcome == .true)
    }

    // MARK: - Pairs

    /// "0 = Neutral, 1 = Enemy, 2 = Ally, 3 = Friend"
    /// (<https://ck.uesp.net/wiki/GetFactionRelation>) — deliberately not the
    /// `XNAM` numbering, which puts Ally at 0.
    @Test func factionRelationUsesTheCreationKitNumbering() throws {
        let cases: [(Faction.CombatReaction, Float)] = [
            (.neutral, 0), (.enemy, 1), (.ally, 2), (.friend, 3)
        ]
        for (reaction, expected) in cases {
            let context = try Self.context(
                subjectMemberships: [(Fixture.Factions.guards, 0)],
                targetMemberships: [(Fixture.Factions.bandit, 0)],
                relations: [
                    Fixture.Relation(Fixture.Factions.guards, Fixture.Factions.bandit, reaction)
                ]
            )

            #expect(try Self.evaluate(
                Index.factionRelation,
                parameter1: ConditionEvaluatorFixture.targetFormID,
                context: context,
                comparison: 0,
                value: expected
            ).outcome == .true)
        }
    }

    /// Two actors whose factions say nothing about each other are Neutral, the
    /// relation the Creation Kit calls the default "even if you don't specify
    /// it" — and the function has no fifth value to report "unrelated" with.
    @Test func anUnrelatedPairIsNeutral() throws {
        let context = try Self.context(
            subjectMemberships: [(Fixture.Factions.guards, 0)],
            targetMemberships: [(Fixture.Factions.bandit, 0)]
        )

        let result = try Self.evaluate(
            Index.factionRelation,
            parameter1: ConditionEvaluatorFixture.targetFormID,
            context: context,
            comparison: 0,
            value: 0
        )
        #expect(result.outcome == .true)
        #expect(result.tally.isClean)
    }

    /// "4 Lover ... -4 Archnemesis" (<https://ck.uesp.net/wiki/GetRelationshipRank>).
    /// The record is authored parent-toward-child and the lookup has to find it
    /// from either side.
    @Test func relationshipRankReadsTheRecordInBothOrders() throws {
        let pairs = [Fixture.Pair(Fixture.Actors.cityGuard, Fixture.Actors.bandit, .ally)]
        let forward = try Self.context(
            pairs: pairs,
            subjectBase: Fixture.Actors.cityGuard,
            targetBase: Fixture.Actors.bandit
        )
        let reversed = try Self.context(
            pairs: pairs,
            subjectBase: Fixture.Actors.bandit,
            targetBase: Fixture.Actors.cityGuard
        )

        for context in [forward, reversed] {
            #expect(try Self.evaluate(
                Index.relationshipRank,
                parameter1: ConditionEvaluatorFixture.targetFormID,
                context: context,
                comparison: 0,
                value: 3 // Ally
            ).outcome == .true)
        }
    }

    /// A scripted rank wins over the record, which is what `SetRelationshipRank`
    /// means, and it is the only layer that can name the player.
    @Test func aScriptedRankWinsOverTheRecord() throws {
        let context = try Self.context(
            pairs: [Fixture.Pair(Fixture.Actors.cityGuard, Fixture.Actors.bandit, .ally)],
            subjectBase: Fixture.Actors.cityGuard,
            targetBase: Fixture.Actors.bandit,
            subjectRelationships: [(Self.target, -4)]
        )

        #expect(try Self.evaluate(
            Index.relationshipRank,
            parameter1: ConditionEvaluatorFixture.targetFormID,
            context: context,
            comparison: 0,
            value: -4 // Archnemesis
        ).outcome == .true)
    }

    /// A pair nothing names is a gap rather than 0, because 0 is Acquaintance —
    /// a rank a record authors deliberately.
    @Test func anUnnamedPairIsAGapRatherThanAcquaintance() throws {
        let result = try Self.evaluate(
            Index.relationshipRank,
            parameter1: ConditionEvaluatorFixture.targetFormID,
            context: Self.context(),
            comparison: 0,
            value: 0
        )

        #expect(!result.outcome.isTrue)
        #expect(result.outcome.failures == [.unavailableFactions])
    }

    /// A Very Aggressive actor attacks Neutrals, so an unrelated stranger is
    /// hostile to it and an Aggressive one is not — the same table
    /// `HostilityDerivation` answers the combat loop with.
    @Test func isHostileToActorFollowsTheDerivation() throws {
        let angry = try Self.context(subjectAggression: .veryAggressive)
        let calm = try Self.context(subjectAggression: .aggressive)

        #expect(try Self.evaluate(
            Index.hostileToActor,
            parameter1: ConditionEvaluatorFixture.targetFormID,
            context: angry
        ).outcome == .true)
        #expect(try Self.evaluate(
            Index.hostileToActor,
            parameter1: ConditionEvaluatorFixture.targetFormID,
            context: calm
        ).outcome == .false)
    }

    /// An actor no cell has streamed carries no profile, and every function
    /// about it reports that rather than answering "belongs to nothing".
    @Test func anActorWithNoProfileIsAGap() throws {
        var context = try ConditionEvaluatorFixture.populatedContext()
        context.factions = try FactionConditionResolution(
            factions: Fixture.factionStore(),
            sourcePlugin: Fixture.pluginName,
            derivation: Fixture.derivation(),
            profiles: [:]
        )

        let result = try Self.evaluate(
            Index.inFaction, parameter1: Fixture.Factions.guards, context: context
        )
        #expect(result.outcome.failures == [.unavailableFactions])
    }

    /// An empty seam — every synthetic scene — reports the gap rather than
    /// answering for an engine that has no factions loaded at all.
    @Test func anEmptySeamIsAGap() throws {
        let context = try ConditionEvaluatorFixture.populatedContext()

        for index in [Index.inFaction, Index.rank] {
            let result = try Self.evaluate(
                index, parameter1: Fixture.Factions.guards, context: context
            )
            #expect(result.outcome.failures == [.unavailableFactions])
        }
    }
}

/// The fixture half, in an extension so the suite's `@Test` body stays inside the
/// strict type-length cap.
@MainActor
extension ConditionFunctionsFactionTests {
    private static func context(
        subjectMemberships: [(faction: UInt32, rank: Int8)] = [],
        targetMemberships: [(faction: UInt32, rank: Int8)] = [],
        relations: [Fixture.Relation] = [],
        pairs: [Fixture.Pair] = [],
        subjectBase: UInt32 = Fixture.Actors.cityGuard,
        targetBase: UInt32 = Fixture.Actors.bandit,
        subjectRelationships: [(other: ReferenceKey, rank: Int8)] = [],
        subjectAggression: ActorAggression = .aggressive
    ) throws -> ConditionContext {
        var context = try ConditionEvaluatorFixture.populatedContext()
        context.factions = try FactionConditionResolution(
            factions: Fixture.factionStore(relations: relations),
            sourcePlugin: Fixture.pluginName,
            derivation: Fixture.derivation(relations: relations, pairs: pairs),
            profiles: [
                subject: Fixture.profile(
                    actor: subjectBase,
                    memberships: subjectMemberships,
                    relationships: subjectRelationships,
                    aggression: subjectAggression,
                    key: subject
                ),
                target: Fixture.profile(
                    actor: targetBase,
                    memberships: targetMemberships,
                    key: target
                )
            ]
        )
        return context
    }

    private static func evaluate(
        _ index: UInt16,
        parameter1: UInt32,
        context: ConditionContext,
        comparison: UInt8 = 0,
        value: Float = 1
    ) throws -> (outcome: ConditionOutcome, tally: ConditionTally) {
        var evaluator = ConditionEvaluator(context: context)
        let outcome = try evaluator.evaluate(ConditionEvaluatorFixture.comparing(
            functionIndex: index,
            comparison,
            value,
            parameter1: parameter1
        ))
        return (outcome, evaluator.tally)
    }

    /// `GetFactionRankDifference` is the one function here with two parameters,
    /// so it cannot go through the shared one-parameter helper.
    private static func evaluateRankDifference(
        context: ConditionContext,
        comparison: UInt8 = 0,
        value: Float = 1
    ) throws -> (outcome: ConditionOutcome, tally: ConditionTally) {
        var evaluator = ConditionEvaluator(context: context)
        let outcome = try evaluator.evaluate(ConditionEvaluatorFixture.condition(
            operatorBits: comparison,
            comparisonValue: value.bitPattern,
            functionIndex: Index.rankDifference,
            parameter1: Fixture.Factions.guards,
            parameter2: ConditionEvaluatorFixture.targetFormID
        ))
        return (outcome, evaluator.tally)
    }
}
