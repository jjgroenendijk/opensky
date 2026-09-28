// The three dialogue condition functions (issue #426): GetIsVoiceType,
// GetIsAliasRef and IsInDialogueWithPlayer, evaluated against synthetic state
// through the `ConditionContext` dialogue, alias and reference seams.
//
// Indices are the raw on-disk numbers from xEdit's condition-function table;
// the Creation Kit spells each 4096 higher. Every condition is a real 32-byte
// CTDA decoded through `Condition(ctda:)`, so nothing here reads game data.

import Foundation
@testable import opensky
import Testing

@MainActor
@Suite("Dialogue condition functions")
struct DialogueConditionFunctionTests {
    private let voiceType = FormID(0x0000_0700)
    private let otherVoice = FormID(0x0000_0701)
    private let quest = FormID(0x0100)
    /// The placement that fills alias 0, and the base object it stands for.
    private let aliasReference: UInt32 = 0x0000_0500
    private let aliasBase: UInt32 = 0x0000_0900

    private var speaker: ReferenceKey {
        ConditionEvaluatorFixture.key(ConditionEvaluatorFixture.subjectFormID)
    }

    private func evaluate(
        _ condition: Condition,
        _ context: ConditionContext
    ) -> (outcome: ConditionOutcome, tally: ConditionTally) {
        var evaluator = ConditionEvaluator(context: context)
        let outcome = evaluator.evaluate(condition)
        return (outcome, evaluator.tally)
    }

    private func populated(dialogue: DialogueResolution) throws -> ConditionContext {
        try ConditionContext(
            dialogue: dialogue,
            references: ConditionEvaluatorFixture.references([
                (
                    formID: ConditionEvaluatorFixture.subjectFormID,
                    base: ConditionEvaluatorFixture.subjectBase
                )
            ]),
            subject: speaker,
            target: .player
        )
    }

    // MARK: - GetIsVoiceType (426)

    /// The documented answer: 1 when the run-on actor's VTCK is the one the
    /// parameter names, 0 when it is a different voice type.
    @Test func voiceTypeMatchesAndMismatches() throws {
        let context = try populated(
            dialogue: DialogueResolution(voiceTypes: [speaker: voiceType])
        )
        let matching = try ConditionEvaluatorFixture.condition(
            comparisonValue: Float(1).bitPattern,
            functionIndex: 426,
            parameter1: voiceType.rawValue
        )
        #expect(evaluate(matching, context).outcome.isTrue)

        let other = try ConditionEvaluatorFixture.condition(
            comparisonValue: Float(1).bitPattern,
            functionIndex: 426,
            parameter1: otherVoice.rawValue
        )
        let result = evaluate(other, context)
        #expect(!result.outcome.isTrue)
        // A mismatch is a real answer, so nothing is tallied as a coverage gap.
        #expect(result.outcome.isConclusive)
    }

    /// An actor this session resolved no voice type for is a reason-tagged
    /// false with its own tally bucket, never a convincing mismatch.
    @Test func anUnknownVoiceTypeIsAnHonestGap() throws {
        let context = try populated(dialogue: .empty)
        let condition = try ConditionEvaluatorFixture.condition(
            comparisonValue: Float(1).bitPattern,
            functionIndex: 426,
            parameter1: voiceType.rawValue
        )
        let result = evaluate(condition, context)
        #expect(!result.outcome.isTrue)
        #expect(result.outcome.failures == [.unavailableDialogue])
        #expect(result.tally.unavailableDialogue == 1)
    }

    // MARK: - GetIsAliasRef (566)

    /// True when the run-on reference is the one filling the named alias of the
    /// context's quest, false when it is a different reference.
    @Test func aliasRefComparesAgainstTheFilledAlias() throws {
        let store = WorldStateStore()
        let runtime = try questRuntime(store)
        try runtime.startQuest(quest)
        var context = try ConditionContext(
            aliases: runtime.aliasResolution(),
            aliasQuest: quest,
            references: ConditionEvaluatorFixture.references(
                [(formID: aliasReference, base: aliasBase)], plugin: "test.esm"
            ),
            subject: ConditionEvaluatorFixture.key(aliasReference, plugin: "test.esm")
        )
        let condition = try ConditionEvaluatorFixture.condition(
            comparisonValue: Float(1).bitPattern, functionIndex: 566
        )
        #expect(evaluate(condition, context).outcome.isTrue)

        context.subject = ConditionEvaluatorFixture.key(0x0000_0501, plugin: "test.esm")
        #expect(!evaluate(condition, context).outcome.isTrue)
    }

    /// Without a quest scope there is no alias table to be right or wrong
    /// about, so the answer is a reason-tagged parameter failure rather than 0.
    @Test func aliasRefWithoutAQuestScopeIsAParameterFailure() throws {
        let store = WorldStateStore()
        let runtime = try questRuntime(store)
        try runtime.startQuest(quest)
        let context = try ConditionContext(
            aliases: runtime.aliasResolution(),
            aliasQuest: nil,
            references: ConditionEvaluatorFixture.references(
                [(formID: aliasReference, base: aliasBase)], plugin: "test.esm"
            ),
            subject: ConditionEvaluatorFixture.key(aliasReference, plugin: "test.esm")
        )
        let condition = try ConditionEvaluatorFixture.condition(
            comparisonValue: Float(1).bitPattern, functionIndex: 566
        )
        #expect(evaluate(condition, context).outcome.failures == [.unresolvedParameter(566)])
    }

    // MARK: - IsInDialogueWithPlayer (249)

    /// True only for the actor the player is currently talking to. An empty
    /// seam answers 0 rather than failing: "nobody is talking to the player" is
    /// a real answer.
    @Test func inDialogueTracksTheOpenConversation() throws {
        let condition = try ConditionEvaluatorFixture.condition(
            comparisonValue: Float(1).bitPattern, functionIndex: 249
        )
        let idle = try populated(dialogue: .empty)
        let idleResult = evaluate(condition, idle)
        #expect(!idleResult.outcome.isTrue)
        #expect(idleResult.outcome.isConclusive)

        let talking = try populated(dialogue: DialogueResolution().talking(to: speaker))
        #expect(evaluate(condition, talking).outcome.isTrue)

        let elsewhere = try populated(
            dialogue: DialogueResolution().talking(to: .player)
        )
        #expect(!evaluate(condition, elsewhere).outcome.isTrue)
    }

    // MARK: - Registry

    /// All three are registered, so a vanilla condition naming one is answered
    /// rather than counted as an unknown function.
    @Test func allThreeAreRegistered() {
        let registry = ConditionFunctionRegistry.standard
        #expect(registry[426]?.name == "GetIsVoiceType")
        #expect(registry[566]?.name == "GetIsAliasRef")
        #expect(registry[249]?.name == "IsInDialogueWithPlayer")
    }

    // MARK: - Private

    /// One quest with a forced-reference alias, so `GetIsAliasRef` has a filled
    /// table to compare against.
    private func questRuntime(_ store: WorldStateStore) throws -> QuestRuntime {
        try QuestRuntime(
            store: store,
            quests: QuestFixture.store(QuestFixture.record(
                formID: 0x0100,
                fields: QuestFixture.editorID("OpenSkyDialogueAlias")
                    + QuestFixture.general(type: 1)
                    + QuestFixture.marker("ANAM")
                    + QuestFixture.alias(
                        id: 0,
                        name: "Speaker",
                        fill: QuestFixture.word("ALFR", aliasReference)
                    )
            ))
        )
    }
}
