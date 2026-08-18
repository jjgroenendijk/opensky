// The spell natives' effect, dispel and cast halves (issue #474, roadmap item
// 19.11), split out of `PapyrusNativeSpellTests.swift` when that suite reached
// the strict-lint type-body cap.
//
// The seam is the one the file already had: the half above answers "does the
// spellbook see what a script did", this half answers "does the effect list and
// the cast loop". Both drive the same fixture.
//
// Fixtures are synthetic — never extracted game files (AGENTS.md "Legal & IP
// boundary").

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct PapyrusNativeSpellEffectTests {
    private typealias Fixture = PapyrusNativeSpellTests.Fixture

    @discardableResult
    private func call(
        _ scriptName: String,
        _ functionName: String,
        _ fixture: Fixture,
        receiver: PapyrusObjectHandle?,
        arguments: [PapyrusValue] = [],
        returnType: PapyrusType = .none
    ) -> PapyrusNativeResult {
        fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            scriptName, functionName, receiver: receiver,
            arguments: arguments, returnType: returnType
        ))
    }

    /// The object handle a script would hold for one of the fixture's records.
    private func spellHandle(
        _ objectID: UInt32,
        _ fixture: Fixture
    ) -> PapyrusValue {
        .object(fixture.session.world.objectHandle(for: SpellbookFixture.key(objectID)))
    }

    // MARK: - Effects

    /// One stored effect of `effect`, sourced to `spell`, on the fixture actor.
    private func applyEffect(
        _ effect: UInt32,
        from spell: UInt32,
        _ fixture: Fixture,
        mode: ActiveEffectMode = .modifier
    ) {
        let state = fixture.effects.runtime.state(of: fixture.holder)
        fixture.effects.runtime.write(
            state.adding(ActiveEffect(
                sequence: state.nextSequence,
                source: ActiveEffectSource(
                    kind: .spell, record: SpellbookFixture.key(spell)
                ),
                effect: SpellbookFixture.key(effect),
                mode: mode,
                isDetrimental: false,
                duration: 30,
                values: [ActiveEffectValue(index: 24, magnitude: 10)]
            )),
            for: fixture.holder
        )
    }

    @Test func hasMagicEffectAndItsKeywordVariantReadTheStoredEffects() throws {
        let fixture = try PapyrusNativeSpellTests.fixture()
        applyEffect(
            SpellbookFixture.restoreHealth,
            from: SpellbookFixture.Spell.fastHealing,
            fixture
        )
        #expect(call(
            "Actor", "HasMagicEffect", fixture, receiver: fixture.receiver,
            arguments: [spellHandle(SpellbookFixture.restoreHealth, fixture)],
            returnType: .boolean
        ) == .returned(.boolean(true)))
        #expect(call(
            "Actor", "HasMagicEffect", fixture, receiver: fixture.receiver,
            arguments: [spellHandle(SpellbookFixture.fireDamage, fixture)],
            returnType: .boolean
        ) == .returned(.boolean(false)))
        #expect(call(
            "Actor", "HasMagicEffectWithKeyword", fixture, receiver: fixture.receiver,
            arguments: [spellHandle(SpellbookFixture.restorationKeyword, fixture)],
            returnType: .boolean
        ) == .returned(.boolean(true)))
    }

    @Test func dispelSpellRemovesOnlyThatSpellsEffects() throws {
        let fixture = try PapyrusNativeSpellTests.fixture()
        applyEffect(
            SpellbookFixture.restoreHealth,
            from: SpellbookFixture.Spell.fastHealing,
            fixture
        )
        applyEffect(
            SpellbookFixture.fireDamage,
            from: SpellbookFixture.Spell.firebolt,
            fixture
        )
        #expect(call(
            "Actor", "DispelSpell", fixture, receiver: fixture.receiver,
            arguments: [spellHandle(SpellbookFixture.Spell.fastHealing, fixture)],
            returnType: .boolean
        ) == .returned(.boolean(true)))
        let remaining = fixture.effects.runtime.active(on: fixture.holder)
        #expect(remaining.map(\.effect)
            == [SpellbookFixture.key(SpellbookFixture.fireDamage)])
        // Nothing left from that spell, so a second dispel reports no change.
        #expect(call(
            "Actor", "DispelSpell", fixture, receiver: fixture.receiver,
            arguments: [spellHandle(SpellbookFixture.Spell.fastHealing, fixture)],
            returnType: .boolean
        ) == .returned(.boolean(false)))
    }

    @Test func dispelAllSpellsSparesAnAbilityAndAConstantEffect() throws {
        let fixture = try PapyrusNativeSpellTests.fixture()
        applyEffect(
            SpellbookFixture.restoreHealth,
            from: SpellbookFixture.Spell.fastHealing,
            fixture
        )
        // `resistFire` is authored as an ability, which the wiki lists among
        // the exceptions a dispel does not touch.
        applyEffect(
            SpellbookFixture.fortifyResistFire,
            from: SpellbookFixture.Spell.resistFire,
            fixture
        )
        // A constant effect is the worn-enchantment shape and is spared too.
        applyEffect(
            SpellbookFixture.fireDamage,
            from: SpellbookFixture.Spell.firebolt,
            fixture,
            mode: .constant
        )
        call("Actor", "DispelAllSpells", fixture, receiver: fixture.receiver)
        #expect(Set(fixture.effects.runtime.active(on: fixture.holder).map(\.effect)) == [
            SpellbookFixture.key(SpellbookFixture.fortifyResistFire),
            SpellbookFixture.key(SpellbookFixture.fireDamage)
        ])
    }

    // MARK: - Casting

    @Test func spellCastAppliesASelfDeliverySpellToItsCaster() throws {
        let fixture = try PapyrusNativeSpellTests.fixture()
        let spell = fixture.session.world.objectHandle(
            for: SpellbookFixture.key(SpellbookFixture.Spell.fastHealing)
        )
        #expect(call(
            "Spell", "Cast", fixture, receiver: spell,
            arguments: [.object(fixture.receiver)]
        ) == .returned(.none))
        #expect(fixture.casterWorld.applications.map(\.target) == [fixture.key])
        #expect(fixture.casterWorld.applications.first?.caster == fixture.key)
    }

    @Test func spellCastAtANamedTargetLandsOnThatTarget() throws {
        let fixture = try PapyrusNativeSpellTests.fixture()
        let spell = fixture.session.world.objectHandle(
            for: SpellbookFixture.key(SpellbookFixture.Spell.firebolt)
        )
        let target = fixture.session.world.objectHandle(for: fixture.targetKey)
        #expect(call(
            "Spell", "Cast", fixture, receiver: spell,
            arguments: [.object(fixture.receiver), .object(target)]
        ) == .returned(.none))
        // The named target goes through the landed-spell seam rather than the
        // caster's aim ray, so nothing was fired and nothing was aimed.
        #expect(fixture.casterWorld.spellHits.count == 1)
        #expect(fixture.casterWorld.spellHits.first?.targets.map(\.key)
            == [fixture.targetKey])
        #expect(fixture.casterWorld.firedProjectiles.isEmpty)
        #expect(fixture.casterWorld.aimCasters.isEmpty)
    }

    @Test func castingASpellThisLoadOrderDoesNotCarryFails() throws {
        let fixture = try PapyrusNativeSpellTests.fixture()
        let stranger = fixture.session.world.objectHandle(
            for: .plugin(name: PapyrusWorldFixture.pluginName, objectID: 0x0000_0DED)
        )
        #expect(PapyrusWorldFixture.isInvalidArguments(call(
            "Spell", "Cast", fixture, receiver: stranger,
            arguments: [.object(fixture.receiver)]
        )))
    }

    // MARK: - Gaps

    @Test func aSessionWithNoSpellbookFailsRatherThanAnswering() throws {
        let fixture = try PapyrusNativeSpellTests.fixture()
        fixture.session.bridge.casterRuntime = { nil }
        let spell = spellHandle(SpellbookFixture.Spell.fastHealing, fixture)
        #expect(PapyrusWorldFixture.isInvalidArguments(call(
            "Actor", "HasSpell", fixture, receiver: fixture.receiver,
            arguments: [spell], returnType: .boolean
        )))
        #expect(call(
            "Actor", "AddSpell", fixture, receiver: fixture.receiver,
            arguments: [spell], returnType: .boolean
        ) == .returned(.boolean(false)))
    }

    @Test func everySpellNativeIsRegistered() throws {
        let registry = try PapyrusNativeSpellTests.fixture().registry
        let actorNames = [
            "AddSpell", "RemoveSpell", "HasSpell", "EquipSpell", "UnequipSpell",
            "GetEquippedSpell", "HasMagicEffect", "HasMagicEffectWithKeyword",
            "DispelSpell", "DispelAllSpells"
        ]
        for name in actorNames {
            #expect(registry.contains(scriptName: "Actor", functionName: name))
        }
        #expect(registry.contains(scriptName: "Spell", functionName: "Cast"))
    }
}
