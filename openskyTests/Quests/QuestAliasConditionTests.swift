// Conditions against the filled alias table (issue #183): the Quest Alias
// run-on, and the CIS1/CIS2 name override that needed the table to exist.
//
// Every condition is a real 32-byte CTDA decoded through `Condition(ctda:)`,
// and every quest is synthetic `QuestFixture` bytes, so nothing here reads game
// data. The store is @MainActor, so the suite is too.

import Foundation
@testable import opensky
import Testing

@MainActor
@Suite("Quest alias conditions")
struct QuestAliasConditionTests {
    private let quest = FormID(0x0100)
    /// The placement that fills alias 0, and the base object it stands for.
    private let arnielReference: UInt32 = 0x0000_0500
    private let arnielBase: UInt32 = 0x0000_0900

    /// One quest with a required forced-reference alias named "Arniel" and an
    /// optional one that never fills.
    private func quests(_ store: WorldStateStore) throws -> QuestRuntime {
        try QuestRuntime(
            store: store,
            quests: QuestFixture.store(QuestFixture.record(
                formID: 0x0100,
                fields: QuestFixture.editorID("MGRArniel01")
                    + QuestFixture.general(type: 1)
                    + QuestFixture.marker("ANAM")
                    + QuestFixture.alias(
                        id: 0,
                        name: "Arniel",
                        fill: QuestFixture.word("ALFR", arnielReference)
                    )
                    + QuestFixture.alias(id: 1, name: "Book", flags: 0x02)
            ))
        )
    }

    /// Context whose reference index holds the placement alias 0 fills, with
    /// no subject and no target: only the alias run-on can name it.
    private func context(_ runtime: QuestRuntime, aliasQuest: FormID?) throws -> ConditionContext {
        try ConditionContext(
            quests: runtime.resolution(),
            aliases: runtime.aliasResolution(),
            aliasQuest: aliasQuest,
            references: ConditionEvaluatorFixture.references(
                [(formID: arnielReference, base: arnielBase)], plugin: "test.esm"
            )
        )
    }

    /// `GetIsID(base) == 1` running on quest alias `alias`.
    private func isID(alias: Int32) throws -> Condition {
        try ConditionEvaluatorFixture.condition(
            comparisonValue: Float(1).bitPattern,
            functionIndex: 72,
            parameter1: arnielBase,
            runOn: 5,
            parameter3: alias
        )
    }

    // MARK: - Run-on 5

    /// Run-on 5 resolves through the filled table, so a function that needs a
    /// reference answers about the alias's target.
    @Test func aFilledAliasAnswersTheQuestAliasRunOn() throws {
        let store = WorldStateStore()
        let runtime = try quests(store)
        try runtime.startQuest(quest)
        var evaluator = try ConditionEvaluator(context: context(runtime, aliasQuest: quest))

        let outcome = try evaluator.evaluate(isID(alias: 0))
        #expect(outcome.isTrue)
        #expect(outcome.isConclusive)
        #expect(evaluator.tally.unsupportedRunOnTotal == 0)
    }

    /// An empty alias, an alias index the record does not declare, the unused
    /// -1 index and a context with no quest scope are all the same answer: the
    /// run-on is supported and named nothing, which is `unresolvedReference`
    /// rather than `unsupportedRunOn`.
    @Test func anUnfilledAliasIsAReasonTaggedFalse() throws {
        let store = WorldStateStore()
        let runtime = try quests(store)
        try runtime.startQuest(quest)
        var evaluator = try ConditionEvaluator(context: context(runtime, aliasQuest: quest))

        for alias: Int32 in [1, 7, -1] {
            let outcome = try evaluator.evaluate(isID(alias: alias))
            #expect(!outcome.isTrue)
            #expect(outcome.failures == [.unresolvedReference(.questAlias)])
        }

        var scopeless = try ConditionEvaluator(context: context(runtime, aliasQuest: nil))
        let outcome = try scopeless.evaluate(isID(alias: 0))
        #expect(outcome.failures == [.unresolvedReference(.questAlias)])
    }

    /// A stopped quest holds nothing, so the same condition that answered
    /// while it ran stops answering — which is the documented alias lifetime,
    /// not a coverage gap.
    @Test func stoppingTheQuestEmptiesTheRunOn() throws {
        let store = WorldStateStore()
        let runtime = try quests(store)
        try runtime.startQuest(quest)
        try runtime.stopQuest(quest)
        var evaluator = try ConditionEvaluator(context: context(runtime, aliasQuest: quest))

        #expect(try evaluator.evaluate(isID(alias: 0)).failures
            == [.unresolvedReference(.questAlias)])
    }

    // MARK: - CIS1 / CIS2

    /// A CIS1 override names an alias; a filled one resolves to that alias's
    /// ID, so the function reads a real parameter instead of reporting one it
    /// cannot read.
    @Test func aCIS1NameResolvesForAFilledAlias() throws {
        let store = WorldStateStore()
        let runtime = try quests(store)
        try runtime.startQuest(quest)
        var condition = try ConditionEvaluatorFixture.isID(arnielBase)
        condition.parameter1Name = "Arniel"
        let call = try ConditionCall(
            condition: condition,
            context: context(runtime, aliasQuest: quest)
        )

        #expect(call.parameter1?.rawValue == 0)
        #expect(try call.aliasReference(#require(call.parameter1))
            == .plugin(name: "test.esm", objectID: arnielReference))
    }

    /// An unfilled alias, an alias name the quest does not declare, and a
    /// context with no quest scope all leave the parameter unreadable, which
    /// the function turns into `unresolvedParameter`.
    @Test func anUnfilledCIS1NameStaysAReasonTaggedFailure() throws {
        let store = WorldStateStore()
        let runtime = try quests(store)
        try runtime.startQuest(quest)
        let scoped = try context(runtime, aliasQuest: quest)

        for name in ["Book", "NoSuchAlias"] {
            var condition = try ConditionEvaluatorFixture.isID(arnielBase)
            condition.parameter1Name = name
            var evaluator = ConditionEvaluator(context: scoped)
            #expect(evaluator.evaluate(condition).failures == [.unresolvedParameter(72)])
        }

        var condition = try ConditionEvaluatorFixture.isID(arnielBase)
        condition.parameter1Name = "Arniel"
        var scopeless = try ConditionEvaluator(context: context(runtime, aliasQuest: nil))
        #expect(scopeless.evaluate(condition).failures == [.unresolvedParameter(72)])
    }

    /// Without a CIS override the raw parameter word is used unchanged, so the
    /// alias path costs the ordinary case nothing.
    @Test func aParameterWithoutANameOverrideIsUnchanged() throws {
        let store = WorldStateStore()
        let runtime = try quests(store)
        let call = try ConditionCall(
            condition: ConditionEvaluatorFixture.isID(arnielBase),
            context: context(runtime, aliasQuest: quest)
        )
        #expect(call.parameter1?.rawValue == arnielBase)
        #expect(call.parameter2?.rawValue == 0)
    }
}
