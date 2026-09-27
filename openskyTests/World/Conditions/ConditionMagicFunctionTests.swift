// The eight magic condition functions (issue #474, roadmap item 19.11), driven
// through the real evaluator against a synthetic spellbook and effect list.
//
// Function indices here are the raw on-disk numbers (Creation Kit number minus
// 4096) — see the ConditionFunctionsMagic.swift header for the sources.
//
// Fixtures are synthetic — never extracted game files (AGENTS.md "Legal & IP
// boundary").

import Foundation
@testable import opensky
import Testing

@MainActor
struct ConditionMagicFunctionTests {
    private static let hasMagicEffect: UInt16 = 214
    private static let isSpellTarget: UInt16 = 223
    private static let hasSpell: UInt16 = 264
    private static let hasEquippedSpell: UInt16 = 570
    private static let getCurrentCastingType: UInt16 = 571
    private static let getCurrentDeliveryType: UInt16 = 572
    private static let isCasting: UInt16 = 632
    private static let hasMagicEffectKeyword: UInt16 = 699

    /// The subject placement `ConditionEvaluatorFixture` builds, standing in
    /// for the actor every condition below runs against.
    private static let subject = ConditionEvaluatorFixture.key(
        ConditionEvaluatorFixture.subjectFormID
    )

    // MARK: - Fixture

    /// A context whose subject knows `fastHealing`, has it readied in the right
    /// hand, and is carrying one active restore-health effect that spell
    /// applied.
    private static func magicContext(
        knows: [UInt32] = [SpellbookFixture.Spell.fastHealing],
        rightHand: UInt32? = SpellbookFixture.Spell.fastHealing,
        leftHand: UInt32? = nil,
        activeEffects: [UInt32] = [SpellbookFixture.restoreHealth],
        effectSources: [UInt32] = [SpellbookFixture.Spell.fastHealing],
        castingHands: Set<SpellHand> = []
    ) throws -> ConditionContext {
        let index = try SpellbookFixture.index()
        let effects = SpellbookFixture.effectStore(index: index)
        var handSpells: [SpellHand: ReferenceKey] = [:]
        handSpells[.right] = rightHand.map(SpellbookFixture.key)
        handSpells[.left] = leftHand.map(SpellbookFixture.key)
        var context = try ConditionEvaluatorFixture.populatedContext()
        context.magic = MagicConditionResolution(
            spells: SpellStore(index: index, effects: effects),
            effects: effects,
            sourcePlugin: SpellbookFixture.pluginName,
            states: [subject: MagicConditionState(
                knownSpells: Set(knows.map(SpellbookFixture.key)),
                activeEffects: Set(activeEffects.map(SpellbookFixture.key)),
                effectSources: Set(effectSources.map(SpellbookFixture.key)),
                handSpells: handSpells,
                castingHands: castingHands
            )]
        )
        return context
    }

    /// `functionIndex <comparison> value` under run-on 0, which the fixture
    /// binds to the subject.
    private static func evaluate(
        _ functionIndex: UInt16,
        _ comparison: UInt8 = 0,
        _ value: Float = 1,
        runOn: UInt32 = 0,
        parameter1: UInt32 = 0,
        context: ConditionContext
    ) throws -> (outcome: ConditionOutcome, tally: ConditionTally) {
        var evaluator = ConditionEvaluator(context: context)
        let outcome = try evaluator.evaluate(ConditionEvaluatorFixture.comparing(
            functionIndex: functionIndex,
            comparison,
            value,
            runOn: runOn,
            parameter1: parameter1
        ))
        return (outcome, evaluator.tally)
    }

    // MARK: - Knowing a spell

    @Test func hasSpellAnswersFromTheSpellbook() throws {
        let context = try Self.magicContext()
        #expect(try Self.evaluate(
            Self.hasSpell, parameter1: SpellbookFixture.Spell.fastHealing, context: context
        ).outcome == .true)
        // A spell the load order carries and the actor has not learned is a
        // real 0 rather than a coverage gap.
        let unknown = try Self.evaluate(
            Self.hasSpell, parameter1: SpellbookFixture.Spell.firebolt, context: context
        )
        #expect(!unknown.outcome.isTrue)
        #expect(unknown.outcome.isConclusive)
        #expect(unknown.tally.isClean)
    }

    @Test func isSpellTargetComparesTheSourceRecordRatherThanTheEffect() throws {
        let context = try Self.magicContext()
        #expect(try Self.evaluate(
            Self.isSpellTarget,
            parameter1: SpellbookFixture.Spell.fastHealing,
            context: context
        ).outcome == .true)
        // The MGEF the effect is an application of is not the record that
        // applied it, so naming it here is false.
        #expect(try !Self.evaluate(
            Self.isSpellTarget,
            parameter1: SpellbookFixture.restoreHealth,
            context: context
        ).outcome.isTrue)
    }

    // MARK: - Carrying an effect

    @Test func hasMagicEffectAnswersFromTheActiveEffectList() throws {
        let context = try Self.magicContext()
        #expect(try Self.evaluate(
            Self.hasMagicEffect,
            parameter1: SpellbookFixture.restoreHealth,
            context: context
        ).outcome == .true)
        #expect(try !Self.evaluate(
            Self.hasMagicEffect,
            parameter1: SpellbookFixture.fireDamage,
            context: context
        ).outcome.isTrue)
    }

    @Test func hasMagicEffectKeywordReadsTheEffectRecordsKeywords() throws {
        let context = try Self.magicContext()
        #expect(try Self.evaluate(
            Self.hasMagicEffectKeyword,
            parameter1: SpellbookFixture.restorationKeyword,
            context: context
        ).outcome == .true)
        // An effect with no keyword list carries none, so the same keyword is
        // false once the restore effect is gone.
        let noEffects = try Self.magicContext(
            activeEffects: [SpellbookFixture.fireDamage],
            effectSources: []
        )
        #expect(try !Self.evaluate(
            Self.hasMagicEffectKeyword,
            parameter1: SpellbookFixture.restorationKeyword,
            context: noEffects
        ).outcome.isTrue)
    }

    // MARK: - What a hand is doing

    @Test func hasEquippedSpellReadsTheNamedHand() throws {
        let context = try Self.magicContext()
        #expect(try Self.evaluate(
            Self.hasEquippedSpell, parameter1: 1, context: context
        ).outcome == .true)
        #expect(try !Self.evaluate(
            Self.hasEquippedSpell, parameter1: 0, context: context
        ).outcome.isTrue)
    }

    @Test func castingAndDeliveryTypeComeFromTheReadiedSpellsHeader() throws {
        let context = try Self.magicContext()
        // `fastHealing` is fire and forget (1), self delivery (0).
        #expect(try Self.evaluate(
            Self.getCurrentCastingType, 0, 1, parameter1: 1, context: context
        ).outcome == .true)
        #expect(try Self.evaluate(
            Self.getCurrentDeliveryType, 0, 0, parameter1: 1, context: context
        ).outcome == .true)
        // `firebolt` is fire and forget, aimed (2).
        let aimed = try Self.magicContext(
            knows: [SpellbookFixture.Spell.firebolt],
            rightHand: SpellbookFixture.Spell.firebolt
        )
        #expect(try Self.evaluate(
            Self.getCurrentDeliveryType, 0, 2, parameter1: 1, context: aimed
        ).outcome == .true)
        // `healing` is concentration (2).
        let concentration = try Self.magicContext(
            knows: [SpellbookFixture.Spell.healing],
            rightHand: SpellbookFixture.Spell.healing
        )
        #expect(try Self.evaluate(
            Self.getCurrentCastingType, 0, 2, parameter1: 1, context: concentration
        ).outcome == .true)
    }

    @Test func isCastingReadsTheCastStateMachine() throws {
        #expect(try !Self.evaluate(
            Self.isCasting, context: Self.magicContext()
        ).outcome.isTrue)
        #expect(try Self.evaluate(
            Self.isCasting, context: Self.magicContext(castingHands: [.right])
        ).outcome == .true)
    }

    // MARK: - The gaps, kept apart from real answers

    @Test func anEmptyMagicSeamIsAReasonTaggedFalse() throws {
        let context = try ConditionEvaluatorFixture.populatedContext()
        let result = try Self.evaluate(
            Self.hasSpell,
            parameter1: SpellbookFixture.Spell.fastHealing,
            context: context
        )
        #expect(!result.outcome.isTrue)
        #expect(!result.outcome.isConclusive)
        // No store to resolve the parameter through is the record gap, which is
        // reached before the actor is ever looked up.
        #expect(result.tally.unavailableMagic == [.record: 1])
    }

    @Test func anActorTheSeamCarriesNoStateForTalliesSeparately() throws {
        var context = try Self.magicContext()
        context.subject = ConditionEvaluatorFixture.key(
            ConditionEvaluatorFixture.targetFormID
        )
        let result = try Self.evaluate(
            Self.hasSpell,
            parameter1: SpellbookFixture.Spell.fastHealing,
            context: context
        )
        #expect(!result.outcome.isTrue)
        #expect(result.tally.unavailableMagic == [.actor: 1])
    }

    @Test func theVoiceSourceIsAGapRatherThanAnEmptyHand() throws {
        let result = try Self.evaluate(
            Self.hasEquippedSpell, parameter1: 2, context: Self.magicContext()
        )
        #expect(!result.outcome.isTrue)
        #expect(result.tally.unavailableMagic == [.castingSource: 1])
        // A source number the enum does not name is a parameter miss instead.
        let unnamed = try Self.evaluate(
            Self.hasEquippedSpell, parameter1: 9, context: Self.magicContext()
        )
        #expect(unnamed.tally.unresolvedParameters == [Self.hasEquippedSpell: 1])
    }

    @Test func anEmptyHandHasNoCastingTypeToReport() throws {
        let result = try Self.evaluate(
            Self.getCurrentCastingType, 0, 1, parameter1: 0, context: Self.magicContext()
        )
        #expect(!result.outcome.isTrue)
        #expect(result.tally.unavailableMagic == [.equippedSpell: 1])
    }

    /// A parameter naming no record in the load order is a clean false rather
    /// than a gap, and that is `FormIDResolver`'s rule rather than this
    /// function's: an unknown master index resolves against the spelling plugin
    /// itself, so the identity is always real even when nothing carries it. The
    /// record gap is for a session with no store at all, which
    /// `anEmptyMagicSeamIsAReasonTaggedFalse` covers.
    @Test func aParameterNamingNoRecordIsACleanFalse() throws {
        let context = try Self.magicContext()
        let result = try Self.evaluate(
            Self.hasMagicEffect, parameter1: 0x0000_FFFF, context: context
        )
        #expect(!result.outcome.isTrue)
        #expect(result.outcome.isConclusive)
        #expect(result.tally.isClean)
    }

    @Test func everyMagicFunctionIsRegisteredUnderItsXEditIndex() {
        let registry = ConditionFunctionRegistry.standard
        let expected: [UInt16: String] = [
            214: "HasMagicEffect",
            223: "IsSpellTarget",
            264: "HasSpell",
            570: "HasEquippedSpell",
            571: "GetCurrentCastingType",
            572: "GetCurrentDeliveryType",
            632: "IsCasting",
            699: "HasMagicEffectKeyword"
        ]
        for (index, name) in expected.sorted(by: { $0.key < $1.key }) {
            #expect(registry[index]?.name == name)
            #expect(registry[index]?.creationKitIndex == Int(index) + 4096)
        }
    }
}
