// The spell-property condition functions over the synthetic spellbook: the readied
// spell's keywords, the evaluated spell's school, and the one-hand, no-ward answers.

import Foundation
@testable import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagicInterface
import Testing

@MainActor
struct ConditionSpellPropertyTests {
    private static let subject = ConditionEvaluatorFixture
        .key(ConditionEvaluatorFixture.subjectFormID)
    private static let keyword = SpellbookFixture.restorationKeyword

    private static func evaluate(
        _ function: UInt16, equals value: Float,
        parameter1: UInt32 = 0, parameter2: UInt32 = 0,
        evaluating spell: UInt32? = nil,
        potionKeywords: Set<ReferenceKey>? = nil
    ) throws -> ConditionOutcome {
        let index = try SpellbookFixture.index()
        let effects = SpellbookFixture.effectStore(index: index)
        let spells = SpellStore(index: index, effects: effects)
        var context = try ConditionEvaluatorFixture.populatedContext()
        context.magic = MagicConditionResolution(
            spells: spells, effects: effects, sourcePlugin: SpellbookFixture.pluginName,
            states: [subject: MagicConditionState(
                knownSpells: [SpellbookFixture.key(SpellbookFixture.Spell.fastHealing)],
                handSpells: [.right: SpellbookFixture.key(SpellbookFixture.Spell.fastHealing)]
            )]
        )
        context.spellEvaluation = SpellEvaluationResolution(
            spell: spell.flatMap { spells.spell(key: SpellbookFixture.key($0)) },
            potionKeywords: potionKeywords
        )
        var registry = ConditionFunctionRegistry()
        ConditionFunctions.installMagic(&registry)
        var evaluator = ConditionEvaluator(context: context, registry: registry)
        return try evaluator.evaluate(ConditionEvaluatorFixture.condition(
            comparisonValue: value.bitPattern, functionIndex: function,
            parameter1: parameter1, parameter2: parameter2
        ))
    }

    @Test func readiedSpellKeywordComesFromItsEffects() throws {
        #expect(try Self.evaluate(596, equals: 1, parameter1: 1, parameter2: Self.keyword) == .true)
        #expect(try Self.evaluate(596, equals: 0, parameter1: 0, parameter2: Self.keyword) == .true)
    }

    @Test func evaluatedSpellAnswersKeywordAndSchool() throws {
        let healing = SpellbookFixture.Spell.fastHealing
        let bolt = SpellbookFixture.Spell.firebolt
        #expect(try Self
            .evaluate(693, equals: 1, parameter1: Self.keyword, evaluating: healing) == .true)
        #expect(try Self
            .evaluate(693, equals: 0, parameter1: Self.keyword, evaluating: bolt) == .true)
        #expect(try Self.evaluate(696, equals: 1, parameter1: 20, evaluating: bolt) == .true)
        #expect(try Self.evaluate(693, equals: 0, parameter1: Self.keyword).failures
            == [.unavailableMagic(.equippedSpell)])
    }

    @Test func aDrunkPotionAnswersKeywordFromItsEffects() throws {
        let restoration = SpellbookFixture.key(Self.keyword)
        #expect(try Self.evaluate(
            693, equals: 1, parameter1: Self.keyword, potionKeywords: [restoration]
        ) == .true)
        #expect(try Self.evaluate(693, equals: 0, parameter1: Self.keyword, potionKeywords: [])
            == .true)
    }

    @Test func singleHandAndNoWard() throws {
        #expect(try Self.evaluate(627, equals: 0) == .true)
        #expect(try Self.evaluate(602, equals: 1, parameter1: 0) == .true)
        #expect(try Self.evaluate(602, equals: 0, parameter1: 1) == .true)
    }

    @Test func alchemyNeedsAnAlchemyEvaluation() throws {
        #expect(try Self.evaluate(500, equals: 0).failures == [.unavailableData(.alchemy)])
    }

    /// An ability's effects count even while none is active; an aimed spell counts
    /// only while one of its effects acts on the actor.
    @Test func abilitiesAndActiveSourcesReachTheirEffects() throws {
        let index = try SpellbookFixture.index()
        let spells = SpellStore(index: index, effects: SpellbookFixture.effectStore(index: index))
        let ability = SpellbookFixture.key(SpellbookFixture.Spell.resistFire)
        let bolt = SpellbookFixture.key(SpellbookFixture.Spell.firebolt)
        func effects(of spell: ReferenceKey) -> Set<ReferenceKey> {
            Set(spells.spell(key: spell)?.effects.compactMap { $0.effect?.key } ?? [])
        }
        let carried = MagicEffectReach.potentialEffects(
            known: [ability, bolt], sources: [], record: { spells.spell(key: $0) }
        )
        let struck = MagicEffectReach.potentialEffects(
            known: [], sources: [bolt], record: { spells.spell(key: $0) }
        )

        #expect(!effects(of: ability).isEmpty)
        #expect(carried == effects(of: ability))
        #expect(struck == effects(of: bolt))
    }
}
