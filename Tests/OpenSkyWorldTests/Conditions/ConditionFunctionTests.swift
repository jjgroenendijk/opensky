// The condition-function registry, the run-on fallbacks, the identity and
// global functions, and the coverage tally. Time and randomness live in
// ConditionTimeFunctionTests.
//
// Function indices here are the raw on-disk numbers (Creation Kit number minus
// 4096) — see the ConditionFunctions.swift header for the sources.

import Foundation
@testable import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
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
        // The measured keyword, form-list, location, magic, perk, level, base-actor-value,
        // crime-gold, faction, item-count, tempering, lock, actor-body, camera, furniture,
        // skill-use, and cell functions.
        #expect(registry.indices == [
            1, 14, 18, 27, 32, 35, 45, 46, 47, 48, 56, 58, 59, 60, 62, 65, 67, 69, 70, 71, 72,
            73, 74, 75, 77, 80, 91, 102, 103, 130, 131, 136, 149, 159, 170, 180, 181, 182, 185,
            214, 223, 237, 244, 248, 249, 250, 263, 264, 266, 277, 286, 289, 300, 310, 313, 323,
            353, 354, 359, 360, 362, 365, 372, 375, 376, 391, 402, 403, 407, 426, 430, 444, 448,
            449, 453, 459, 476, 515, 516, 517, 518, 522, 523, 543, 550, 555, 560, 561, 562, 565,
            566, 567, 568, 570, 571, 572, 576, 580, 590, 594, 603, 604, 605, 606, 608, 610, 613,
            614, 629, 630, 631, 632, 640, 641, 644, 650, 651, 659, 675, 681, 691, 692, 698, 699,
            700, 719
        ])
        #expect(registry.count == 126)
        #expect(registry.sortedFunctions().map(\.name) == [
            "GetDistance", "GetActorValue", "GetCurrentTime", "GetLineOfSight", "GetInSameCell",
            "GetDisabled", "GetDetected", "GetDead", "GetItemCount", "GetGold",
            "GetQuestRunning", "GetStage", "GetStageDone", "GetFactionRankDifference",
            "IsRaining", "GetLockLevel", "GetInCell", "GetIsRace", "GetIsSex", "GetInFaction",
            "GetIsID", "GetFactionRank", "GetGlobalValue", "IsSnowing", "GetRandomPercent",
            "GetLevel", "GetIsAlerted", "IsTorchOut", "IsShieldOut", "GetPCIsRace",
            "GetPCIsSex", "GetIsReference", "GetIsCurrentWeather", "GetSitting", "GetDayOfWeek",
            "HasSameEditorLocAsRef", "HasSameEditorLocAsRefAlias", "GetEquipped", "IsSwimming",
            "HasMagicEffect", "IsSpellTarget", "GetIsGhost", "GetRestrained", "IsScenePlaying",
            "IsInDialogueWithPlayer", "GetLocationCleared", "IsWeaponOut", "HasSpell",
            "IsPleasant", "GetBaseActorValue", "IsSneaking", "IsInCombat", "IsInInterior",
            "GetInWorldspace", "GetPairedAnimation", "GetCombatState", "IsActor", "IsEssential",
            "GetInCurrentLoc", "GetInCurrentLocAlias", "HasLinkedRef", "IsChild", "IsInList",
            "GetCrimeGoldViolent", "GetCrimeGoldNonviolent", "IsPC1stPerson",
            "IsBribedbyPlayer", "GetRelationshipRank", "GetVATSValue", "GetIsVoiceType",
            "GetHealthPercentage", "GetInCurrentLocFormList", "HasPerk", "GetFactionRelation",
            "GetPlayerTeammate", "GetCrimeGold", "IsProtected", "GetVATSRightAreaFree",
            "GetVATSLeftAreaFree", "GetVATSBackAreaFree", "GetVATSFrontAreaFree",
            "GetVATSRightTargetVisible", "GetVATSLeftTargetVisible", "GetQuestCompleted",
            "IsSceneActionComplete", "HasLoaded3D", "HasKeyword", "HasRefType",
            "LocationHasKeyword", "GetIsEditorLocation", "GetIsAliasRef", "GetIsEditorLocAlias",
            "IsSprinting", "HasEquippedSpell", "GetCurrentCastingType",
            "GetCurrentDeliveryType", "GetEventData", "IsBleedingOut", "IsInScene",
            "GetIsFlying", "IsInSameCurrentLocAsRef", "IsInSameCurrentLocAsRefAlias",
            "LocAliasIsLocation", "GetKeywordDataForLocation", "GetKeywordDataForAlias",
            "LocAliasHasKeyword", "IsFurnitureAnimType", "IsFurnitureEntryType",
            "GetVMQuestVariable", "GetVMScriptVariable", "IsEnteringInteractionQuick",
            "IsCasting", "GetActorValuePercent", "IsUnique", "IsInFurnitureState", "IsLinkedTo",
            "GetKeywordDataForCurrentLocation", "EPTemperingItemIsEnchanted",
            "GetGraphVariableInt", "EPMagic_IsAdvanceSkill",
            "EPModSkillUsage_AdvanceObjectHasKeyword", "EPModSkillUsage_IsAdvanceAction",
            "IsAllowedToFly", "HasMagicEffectKeyword", "IsCommandedActor", "IsHostileToActor"
        ])
        // The Creation Kit spells every index 4096 higher than the plugin does.
        #expect(registry.sortedFunctions().map(\.creationKitIndex) == registry.indices.map {
            Int($0) + 4096
        })
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
        // Quest Alias (5), Combat Target (3), and Event Data (7) are absent:
        // they resolve now. Event data is covered by `EventDataConditionTests`.
        // They are covered by `QuestAliasConditionTests` and
        // `ConditionActorFunctionTests`.
        let cases: [(raw: UInt32, runOn: Condition.RunOnType)] = [
            (4, .linkedReference),
            (6, .packageData),
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
            "linkedReference", "packageData", "unknown(99)"
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

    // MARK: - IsInInterior

    @Test func isInInteriorReadsTheCellThatHoldsTheSubject() throws {
        var context = try ConditionEvaluatorFixture.populatedContext()
        let subject = try #require(context.subject)
        let condition = try ConditionEvaluatorFixture.condition(
            comparisonValue: Float(1).bitPattern, functionIndex: 300
        )
        context.data = ConditionDataResolution(interiors: [subject: true])
        var inside = ConditionEvaluator(context: context)
        #expect(inside.evaluate(condition).isTrue)

        context.data = ConditionDataResolution(interiors: [subject: false])
        var outside = ConditionEvaluator(context: context)
        let answer = outside.evaluate(condition)
        #expect(!answer.isTrue)
        #expect(answer.isConclusive)

        var unknown = try ConditionEvaluator(context: ConditionEvaluatorFixture.populatedContext())
        #expect(!unknown.evaluate(condition).isConclusive)
    }

    // MARK: - HasLoaded3D

    @Test func hasLoaded3DIsTrueForAReferenceInALoadedCell() throws {
        var context = try ConditionEvaluatorFixture.populatedContext()
        let subject = try #require(context.subject)
        let condition = try ConditionEvaluatorFixture.condition(
            comparisonValue: Float(1).bitPattern, functionIndex: 555
        )
        context.data = ConditionDataResolution(interiors: [subject: false])
        var loaded = ConditionEvaluator(context: context)
        #expect(loaded.evaluate(condition).isTrue)

        context.data = ConditionDataResolution()
        var unloaded = ConditionEvaluator(context: context)
        #expect(!unloaded.evaluate(condition).isTrue)
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
