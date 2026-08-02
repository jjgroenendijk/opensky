// The four quest condition functions (issue #182): GetStage, GetStageDone,
// GetQuestRunning and GetQuestCompleted, evaluated against synthetic quest
// state through the `ConditionContext` quest seam.
//
// Indices are the raw on-disk numbers from xEdit's condition-function table;
// the Creation Kit spells each 4096 higher. Conditions are built in code with
// `ConditionFixture`, so nothing here reads game data.

import Foundation
@testable import opensky
import Testing

@Suite("Quest condition functions")
struct QuestConditionFunctionTests {
    private let mainQuest = FormID(0x0100)
    private let sideQuest = FormID(0x0200)

    private func store() throws -> QuestStore {
        try QuestFixture.store(
            QuestFixture.record(
                formID: 0x0100,
                fields: QuestFixture.editorID("MQ101")
                    + QuestFixture.general(flags: 0x0001, type: 1)
                    + QuestFixture.stage(10)
                    + QuestFixture.logEntry(text: "start")
                    + QuestFixture.stage(20)
                    + QuestFixture.logEntry(text: "middle")
            )
                + QuestFixture.record(
                    formID: 0x0200,
                    fields: QuestFixture.editorID("FreeformRiften")
                        + QuestFixture.general(type: 6)
                )
        )
    }

    /// A context whose quest seam carries `states` over the fixture's
    /// baselines, keyed the way `QuestStore` keys them.
    private func context(
        _ states: [UInt32: QuestRuntimeState] = [:]
    ) throws -> ConditionContext {
        var overrides: [ReferenceKey: QuestRuntimeState] = [:]
        for (objectID, state) in states {
            overrides[GlobalFixture.key(objectID)] = state
        }
        return try ConditionContext(
            quests: QuestResolution(defaults: store(), overrides: overrides)
        )
    }

    private func evaluate(
        _ condition: Condition,
        _ context: ConditionContext
    ) -> ConditionOutcome {
        var evaluator = ConditionEvaluator(context: context)
        return evaluator.evaluate(condition)
    }

    /// One condition comparing a function's return against `value`.
    private func condition(
        _ index: UInt16,
        quest: FormID,
        stage: Int32 = 0,
        equals value: Float
    ) throws -> Condition {
        try ConditionEvaluatorFixture.condition(
            comparisonValue: value.bitPattern,
            functionIndex: index,
            parameter1: quest.rawValue,
            parameter2: UInt32(bitPattern: stage)
        )
    }

    // MARK: - Registration

    @Test func theFourFunctionsAreRegisteredUnderTheirXEditIndices() {
        let registry = ConditionFunctionRegistry.standard
        #expect(registry[56]?.name == "GetQuestRunning")
        #expect(registry[58]?.name == "GetStage")
        #expect(registry[59]?.name == "GetStageDone")
        #expect(registry[543]?.name == "GetQuestCompleted")
        // The Creation Kit spelling of the same indices.
        #expect(registry[58]?.creationKitIndex == 4154)
        #expect(registry[543]?.creationKitIndex == 4639)
        #expect(registry[59]?.parameter2 == .integer)
    }

    // MARK: - GetStage

    /// The highest stage reached, whatever order the stages were reached in.
    @Test func getStageReturnsTheHighestReachedStage() throws {
        let reached = QuestRuntimeState(isRunning: true, stagesReached: [20, 10])
        let context = try context([0x0100: reached])
        #expect(try evaluate(condition(58, quest: mainQuest, equals: 20), context).isTrue)
        #expect(try !evaluate(condition(58, quest: mainQuest, equals: 10), context).isTrue)
    }

    /// A quest that has reached no stage answers 0 rather than failing: the
    /// quest exists, so the engine has a real answer for it.
    @Test func getStageAnswersZeroForAnUntouchedQuest() throws {
        let outcome = try evaluate(condition(58, quest: sideQuest, equals: 0), context())
        #expect(outcome.isTrue)
        #expect(outcome.isConclusive)
    }

    // MARK: - GetStageDone

    /// Only visited stages are done: a lower stage is never implied by a
    /// higher one.
    @Test func getStageDoneAnswersPerVisitedStage() throws {
        let reached = QuestRuntimeState(isRunning: true, stagesReached: [20])
        let context = try context([0x0100: reached])
        #expect(try evaluate(condition(59, quest: mainQuest, stage: 20, equals: 1), context).isTrue)
        #expect(try evaluate(condition(59, quest: mainQuest, stage: 10, equals: 0), context).isTrue)
    }

    /// A stage index outside the uint16 range cannot name a stage, so "not
    /// done" is a real answer rather than a coverage gap.
    @Test func getStageDoneAnswersZeroForAnImpossibleStageIndex() throws {
        let reached = QuestRuntimeState(isRunning: true, stagesReached: [20])
        let context = try context([0x0100: reached])
        let outcome = try evaluate(condition(59, quest: mainQuest, stage: -1, equals: 0), context)
        #expect(outcome.isTrue)
        #expect(outcome.isConclusive)
    }

    // MARK: - GetQuestRunning and GetQuestCompleted

    /// A start-game-enabled quest runs straight off its baseline, with no
    /// runtime state recorded anywhere.
    @Test func getQuestRunningReadsTheBaselineAndTheOverride() throws {
        let untouched = try context()
        #expect(try evaluate(condition(56, quest: mainQuest, equals: 1), untouched).isTrue)
        #expect(try evaluate(condition(56, quest: sideQuest, equals: 0), untouched).isTrue)

        let stopped = try context([0x0100: QuestRuntimeState.dormant])
        #expect(try evaluate(condition(56, quest: mainQuest, equals: 0), stopped).isTrue)
    }

    @Test func getQuestCompletedFollowsTheCompletedFlag() throws {
        let untouched = try context()
        #expect(try evaluate(condition(543, quest: mainQuest, equals: 0), untouched).isTrue)

        let completed = QuestRuntimeState(isRunning: true, isCompleted: true)
        let context = try context([0x0100: completed])
        #expect(try evaluate(condition(543, quest: mainQuest, equals: 1), context).isTrue)
    }

    // MARK: - Failure paths

    /// A parameter naming no quest is a reason-tagged false with its own tally
    /// bucket, never a throw and never a comparison against zero.
    @Test func anUnresolvableQuestIsAReasonTaggedFailure() throws {
        let absent = FormID(0x9999)
        var evaluator = try ConditionEvaluator(context: context())
        let outcome = try evaluator.evaluate([
            condition(58, quest: absent, equals: 0),
            condition(56, quest: absent, equals: 0),
            condition(59, quest: absent, stage: 10, equals: 0),
            condition(543, quest: absent, equals: 0)
        ])
        #expect(!outcome.isTrue)
        #expect(outcome.failures == Array(repeating: .unresolvedQuest(absent), count: 4))
        #expect(evaluator.tally.unresolvedQuestTotal == 4)
        #expect(evaluator.tally.rankedUnresolvedQuests.first?.count == 4)
        #expect(!evaluator.tally.isClean)
        #expect(evaluator.tally.failureTotal == 4)
    }

    /// An empty context defines no quest at all, which is the shape a condition
    /// evaluated before any plugin loaded runs in.
    @Test func anEmptyQuestSeamResolvesNothing() throws {
        let outcome = try evaluate(condition(56, quest: mainQuest, equals: 1), ConditionContext())
        #expect(!outcome.isTrue)
        #expect(outcome.failures == [.unresolvedQuest(mainQuest)])
    }
}
