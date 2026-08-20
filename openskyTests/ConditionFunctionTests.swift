// The condition-function registry, the run-on fallbacks, the identity and
// global functions, and the coverage tally. Time and randomness live in
// ConditionTimeFunctionTests.
//
// Function indices here are the raw on-disk numbers (Creation Kit number minus
// 4096) — see the ConditionFunctions.swift header for the sources.

import Foundation
@testable import opensky
import Testing

struct ConditionFunctionTests {
    private static let getCurrentTime: UInt16 = 18
    private static let getIsID: UInt16 = 72
    private static let getGlobalValue: UInt16 = 74
    private static let subjectBase = ConditionEvaluatorFixture.subjectBase
    private static let targetBase = ConditionEvaluatorFixture.targetBase
    private static let flagFormID = ConditionEvaluatorFixture.flagFormID

    // MARK: - Registry

    @Test func registryDescribesTheImplementedFunctions() {
        let registry = ConditionFunctionRegistry.standard
        // Issue #455 adds the fourteen measured M18 keyword, form-list and
        // location functions; issue #474 adds the eight measured magic ones;
        // issue #497 adds `HasPerk`, which is what makes a perk rank chain
        // switch itself off; issue #499 adds `GetLevel` and
        // `GetBaseActorValue`, which is what every vanilla perk requirement is
        // stated with.
        #expect(registry.indices == [
            1, 14, 18, 27, 35, 45, 46, 56, 58, 59, 72, 74, 77, 80, 170, 180, 181, 214,
            223, 249, 263, 264, 277, 323, 359, 360, 372, 426, 444, 448, 543, 560, 562,
            565, 566, 567, 570, 571, 572, 603, 604, 605, 610, 632, 640, 699
        ])
        #expect(registry.count == 46)
        #expect(registry.sortedFunctions().map(\.name) == [
            "GetDistance", "GetActorValue", "GetCurrentTime", "GetLineOfSight",
            "GetDisabled", "GetDetected", "GetDead", "GetQuestRunning",
            "GetStage", "GetStageDone", "GetIsID", "GetGlobalValue", "GetRandomPercent",
            "GetLevel",
            "GetDayOfWeek", "HasSameEditorLocAsRef", "HasSameEditorLocAsRefAlias",
            "HasMagicEffect", "IsSpellTarget",
            "IsInDialogueWithPlayer", "IsWeaponOut", "HasSpell", "GetBaseActorValue",
            "GetCombatState",
            "GetInCurrentLoc",
            "GetInCurrentLocAlias", "IsInList", "GetIsVoiceType",
            "GetInCurrentLocFormList", "HasPerk", "GetQuestCompleted", "HasKeyword",
            "LocationHasKeyword", "GetIsEditorLocation", "GetIsAliasRef",
            "GetIsEditorLocAlias", "HasEquippedSpell", "GetCurrentCastingType",
            "GetCurrentDeliveryType", "IsInSameCurrentLocAsRef",
            "IsInSameCurrentLocAsRefAlias", "LocAliasIsLocation", "LocAliasHasKeyword",
            "IsCasting", "GetActorValuePercent", "HasMagicEffectKeyword"
        ])
        // The Creation Kit spells every index 4096 higher than the plugin does.
        #expect(registry.sortedFunctions().map(\.creationKitIndex) == [
            4097, 4110, 4114, 4123, 4131, 4141, 4142, 4152, 4154, 4155, 4168, 4170,
            4173, 4176, 4266, 4276, 4277, 4310, 4319, 4345, 4359, 4360, 4373, 4419, 4455,
            4456, 4468, 4522, 4540, 4544, 4639, 4656, 4658, 4661, 4662, 4663, 4666, 4667,
            4668, 4699, 4700, 4701, 4706, 4728, 4736, 4795
        ])
        #expect(registry[Self.getIsID]?.parameter1 == .formID)
        #expect(registry[Self.getIsID]?.parameter2 == .unused)
        #expect(registry[Self.getGlobalValue]?.parameter1 == .formID)
        #expect(registry[Self.getCurrentTime]?.parameter1 == .unused)
        #expect(registry[9999] == nil)
        #expect(registry.name(for: 9999) == "function 14095")
        #expect(ConditionFunctionRegistry.empty.isEmpty)
    }

    // MARK: - Unknown functions

    @Test func unknownFunctionIsTaggedFalseAndTallied() throws {
        var evaluator = try ConditionEvaluatorFixture.evaluator()
        let condition = try ConditionEvaluatorFixture.comparing(functionIndex: 1234, 0, 1)
        let outcome = evaluator.evaluate(condition)
        #expect(!outcome.isTrue)
        #expect(outcome.failures == [.unknownFunction(1234)])
        _ = evaluator.evaluate(condition)
        #expect(evaluator.tally.unknownFunctionTotal == 2)
        #expect(evaluator.tally.unknownFunctions == [1234: 2])
        let ranked = evaluator.tally.rankedUnknownFunctions()
        #expect(ranked.map(\.name) == ["function 5330"])
        #expect(ranked.map(\.count) == [2])
        #expect(!evaluator.tally.isClean)
    }

    @Test func unknownFunctionTallyCapsTheNameTable() throws {
        var evaluator = try ConditionEvaluatorFixture.evaluator(
            tally: ConditionTally(nameLimit: 2)
        )
        for index: UInt16 in [900, 901, 902, 903, 900] {
            let condition = try ConditionEvaluatorFixture.comparing(functionIndex: index, 0, 1)
            _ = evaluator.evaluate(condition)
        }
        // Two distinct indices are named; the rest still count in the total.
        #expect(evaluator.tally.unknownFunctions == [900: 2, 901: 1])
        #expect(evaluator.tally.unknownFunctionTotal == 5)
        #expect(evaluator.tally.unnamedUnknownFunctions == 2)
    }

    // MARK: - Run-on fallbacks

    @Test func unsupportedRunOnTypesAreTaggedFalse() throws {
        // Quest Alias (5) is deliberately absent: issue #183 made it a
        // supported run-on that resolves through the filled alias table, so an
        // empty one is `unresolvedReference` and is covered by
        // `QuestAliasConditionTests`. Combat Target (3) left this list for the
        // same reason at issue #375, and is covered by
        // `ConditionActorFunctionTests`.
        let cases: [(raw: UInt32, runOn: Condition.RunOnType)] = [
            (4, .linkedReference),
            (6, .packageData),
            (7, .eventData),
            (99, .unknown(99))
        ]
        var evaluator = try ConditionEvaluatorFixture.evaluator()
        for (raw, runOn) in cases {
            let condition = try ConditionEvaluatorFixture.isID(Self.subjectBase, runOn: raw)
            let outcome = evaluator.evaluate(condition)
            #expect(!outcome.isTrue, "run-on \(raw) should not evaluate")
            #expect(outcome.failures == [.unsupportedRunOn(runOn)])
        }
        #expect(evaluator.tally.unsupportedRunOnTotal == cases.count)
        #expect(evaluator.tally.rankedUnsupportedRunOns.map(\.name) == [
            "eventData", "linkedReference", "packageData", "unknown(99)"
        ])
        // A context with no quest scope cannot answer an alias run-on, but the
        // reason is that the alias named nothing, not that the run-on is
        // unknown.
        let aliasCondition = try ConditionEvaluatorFixture.isID(Self.subjectBase, runOn: 5)
        #expect(evaluator.evaluate(aliasCondition).failures
            == [.unresolvedReference(.questAlias)])
        #expect(evaluator.tally.rankedUnsupportedRunOns.allSatisfy { $0.count == 1 })
    }

    @Test func unresolvableSubjectTargetAndReferenceAreTaggedFalse() throws {
        // Empty context: nothing is bound and the index is empty.
        var evaluator = ConditionEvaluator(context: ConditionContext())
        let subject = try evaluator.evaluate(
            ConditionEvaluatorFixture.isID(Self.subjectBase, runOn: 0)
        )
        let target = try evaluator.evaluate(
            ConditionEvaluatorFixture.isID(Self.subjectBase, runOn: 1)
        )
        let reference = try evaluator.evaluate(
            ConditionEvaluatorFixture.isID(Self.subjectBase, runOn: 2)
        )
        #expect(subject.failures == [.unresolvedReference(.subject)])
        #expect(target.failures == [.unresolvedReference(.target)])
        #expect(reference.failures == [.unresolvedReference(.reference)])
        #expect(evaluator.tally.unresolvedReferenceTotal == 3)
        #expect(evaluator.tally.rankedUnresolvedReferences.map(\.name) == [
            "reference", "subject", "target"
        ])
        #expect(evaluator.tally.unsupportedRunOnTotal == 0)
    }

    // MARK: - GetIsID

    @Test func getIsIDComparesTheReferenceBaseForm() throws {
        var evaluator = try ConditionEvaluatorFixture.evaluator()
        let subject = try evaluator.evaluate(ConditionEvaluatorFixture.isID(Self.subjectBase))
        let wrongBase = try evaluator.evaluate(ConditionEvaluatorFixture.isID(Self.targetBase))
        let target = try evaluator.evaluate(
            ConditionEvaluatorFixture.isID(Self.targetBase, runOn: 1)
        )
        // Run-on 2 reads the condition's own reference FormID, which the
        // fixture points at the subject placement.
        let explicit = try evaluator.evaluate(
            ConditionEvaluatorFixture.isID(Self.subjectBase, runOn: 2)
        )
        #expect(subject.isTrue)
        #expect(!wrongBase.isTrue)
        #expect(target.isTrue)
        #expect(explicit.isTrue)
        #expect(evaluator.tally.isClean)
    }

    @Test func swapSubjectAndTargetFlagSwapsTheRunOn() throws {
        var evaluator = try ConditionEvaluatorFixture.evaluator()
        // Flag 0x10 makes a Subject run-on read the target and vice versa.
        let swappedSubject = try evaluator.evaluate(
            ConditionEvaluatorFixture.isID(Self.targetBase, flags: 0x10)
        )
        let swappedTarget = try evaluator.evaluate(
            ConditionEvaluatorFixture.isID(Self.subjectBase, runOn: 1, flags: 0x10)
        )
        #expect(swappedSubject.isTrue)
        #expect(swappedTarget.isTrue)
        #expect(evaluator.tally.isClean)
    }

    @Test func namedParameterIsTaggedRatherThanMisread() throws {
        // CIS1 replaces parameter #1 with a quest-alias name, which needs a
        // table OpenSky does not resolve yet — the raw word is then arbitrary.
        var list = ConditionList()
        try list.decode(field: ConditionEvaluatorFixture.field(
            comparisonValue: Float(1).bitPattern,
            functionIndex: Self.getIsID,
            parameter1: Self.subjectBase
        ))
        try list.decode(field: ESMField(type: "CIS1", data: ESMFixture.zstring("SomeAlias")))

        var evaluator = try ConditionEvaluatorFixture.evaluator()
        let outcome = evaluator.evaluate(list)
        #expect(!outcome.isTrue)
        #expect(outcome.failures == [.unresolvedParameter(Self.getIsID)])
        #expect(evaluator.tally.unresolvedParameters == [Self.getIsID: 1])
    }

    // MARK: - GetGlobalValue

    @Test func getGlobalValueReadsTheGlobalsSeam() throws {
        var evaluator = try ConditionEvaluatorFixture.evaluator()
        let present = try ConditionEvaluatorFixture.comparing(
            functionIndex: Self.getGlobalValue, 0, 1, parameter1: Self.flagFormID
        )
        #expect(evaluator.evaluate(present).isTrue)

        let missing = try ConditionEvaluatorFixture.comparing(
            functionIndex: Self.getGlobalValue, 0, 0, parameter1: 0x0000_0777
        )
        let outcome = evaluator.evaluate(missing)
        #expect(!outcome.isTrue)
        #expect(outcome.failures == [.unresolvedGlobal(FormID(0x0000_0777))])
    }
}
