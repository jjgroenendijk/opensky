// The spell natives (issue #474, roadmap item 19.11), invoked through the
// registry against a synthetic actor with a live spellbook, a live effect
// runtime and a live cast loop behind them.
//
// The session is the real one — `PapyrusWorldStateBridge` over a real
// `WorldStateStore`, `SpellbookRuntime` and `CasterRuntime` — rather than a
// fake bridge, for the reason `PapyrusNativeActorTests` uses one: the thing
// worth testing is that a script's `AddSpell` and the panel's Learn button
// reach the same component, so a later `HasSpell` and the spellbook readout
// cannot disagree. Only the world a cast delivers into is faked, since applying
// effects for real needs no more than a recorder here.
//
// Fixtures are synthetic — never extracted game files (AGENTS.md "Legal & IP
// boundary").

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct PapyrusNativeSpellTests {
    static let actorID: UInt32 = 0x0000_0A11
    static let baseID: UInt32 = 0x0000_0B22
    static let targetID: UInt32 = 0x0000_0C33

    /// `ActiveEffectRuntime` is a struct the session owns by value, exactly as
    /// the controller owns it, so the dispel closure needs somewhere to write
    /// the result back to.
    final class EffectBox {
        var runtime: ActiveEffectRuntime

        init(runtime: ActiveEffectRuntime) {
            self.runtime = runtime
        }
    }

    struct Fixture {
        let session: PapyrusWorldFixture.Session
        let registry: PapyrusNativeRegistry
        let receiver: PapyrusObjectHandle
        let key: ReferenceKey
        let targetKey: ReferenceKey
        let caster: CasterRuntime
        let casterWorld: FakeCasterWorld
        let effects: EffectBox
        let holder: ActorValueHolder
    }

    static func fixture() throws -> Fixture {
        let entry = try PapyrusWorldFixture.actorEntry(
            objectID: actorID, base: baseID, scripts: []
        )
        let targetEntry = try PapyrusWorldFixture.actorEntry(
            objectID: targetID, base: baseID, scripts: []
        )
        let session = PapyrusWorldFixture.session(objects: [], entries: [entry, targetEntry])
        PapyrusWorldFixture.drain(session.world)
        let index = try SpellbookFixture.index()
        let effectStore = SpellbookFixture.effectStore(index: index)
        let values = SpellbookFixture.values(store: session.worldState)
        let spellbook = SpellbookRuntime(
            store: session.worldState,
            spells: SpellStore(index: index, effects: effectStore),
            equipSlots: EquipSlotStore(index: index)
        )
        let caster = CasterRuntime(spellbook: spellbook, values: values)
        let casterWorld = FakeCasterWorld()
        caster.attach(world: casterWorld)
        let effects = EffectBox(
            runtime: ActiveEffectRuntime(values: values, effects: effectStore)
        )
        session.bridge.actorValueRuntime = { values }
        session.bridge.casterRuntime = { [weak caster] in caster }
        session.bridge.magicEffectStore = effectStore
        session.bridge.dispelEffects = { holder, predicate in
            effects.runtime.dispel(on: holder, where: predicate)
        }
        session.bridge.applySpellHit = { [weak casterWorld] hit in
            casterWorld?.applySpellHit(hit) ?? SpellHitReport()
        }
        return Fixture(
            session: session,
            registry: PapyrusWorldFixture.registry(for: session),
            receiver: session.world.objectHandle(for: entry.key),
            key: entry.key,
            targetKey: targetEntry.key,
            caster: caster,
            casterWorld: casterWorld,
            effects: effects,
            holder: ActorValueHolder(
                key: entry.key,
                subject: .actor(base: FormID(baseID)),
                cell: PapyrusWorldFixture.cell
            )
        )
    }

    // MARK: - Calling

    @discardableResult
    func call(
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

    /// The object handle a script would hold for one of the fixture's spells.
    private func spellHandle(
        _ objectID: UInt32,
        _ fixture: Fixture
    ) -> PapyrusValue {
        .object(fixture.session.world.objectHandle(for: SpellbookFixture.key(objectID)))
    }

    // MARK: - Knowing

    @Test func addSpellIsVisibleToASubsequentHasSpell() throws {
        let fixture = try Self.fixture()
        let spell = spellHandle(SpellbookFixture.Spell.fastHealing, fixture)
        #expect(call(
            "Actor", "HasSpell", fixture, receiver: fixture.receiver,
            arguments: [spell], returnType: .boolean
        ) == .returned(.boolean(false)))
        #expect(call(
            "Actor", "AddSpell", fixture, receiver: fixture.receiver,
            arguments: [spell, .boolean(true)], returnType: .boolean
        ) == .returned(.boolean(true)))
        #expect(call(
            "Actor", "HasSpell", fixture, receiver: fixture.receiver,
            arguments: [spell], returnType: .boolean
        ) == .returned(.boolean(true)))
        // The write went through `SpellbookRuntime`, so the component the
        // panel and the save read carries it too.
        #expect(fixture.caster.spellbook.knows(
            SpellbookFixture.key(SpellbookFixture.Spell.fastHealing), fixture.holder
        ))
    }

    @Test func addingAKnownSpellAgainReportsNoChange() throws {
        let fixture = try Self.fixture()
        let spell = spellHandle(SpellbookFixture.Spell.fastHealing, fixture)
        call(
            "Actor", "AddSpell", fixture, receiver: fixture.receiver,
            arguments: [spell], returnType: .boolean
        )
        #expect(call(
            "Actor", "AddSpell", fixture, receiver: fixture.receiver,
            arguments: [spell], returnType: .boolean
        ) == .returned(.boolean(false)))
    }

    @Test func removeSpellForgetsItAndReportsWhetherItWasKnown() throws {
        let fixture = try Self.fixture()
        let spell = spellHandle(SpellbookFixture.Spell.fastHealing, fixture)
        call(
            "Actor", "AddSpell", fixture, receiver: fixture.receiver, arguments: [spell]
        )
        #expect(call(
            "Actor", "RemoveSpell", fixture, receiver: fixture.receiver,
            arguments: [spell], returnType: .boolean
        ) == .returned(.boolean(true)))
        #expect(call(
            "Actor", "RemoveSpell", fixture, receiver: fixture.receiver,
            arguments: [spell], returnType: .boolean
        ) == .returned(.boolean(false)))
    }

    // MARK: - Readying

    @Test func equipSpellTeachesTheSpellAndFillsTheNamedHand() throws {
        let fixture = try Self.fixture()
        let spell = spellHandle(SpellbookFixture.Spell.fastHealing, fixture)
        // The wiki's documented courtesy: an actor that does not know the spell
        // is given it rather than refused.
        #expect(call(
            "Actor", "EquipSpell", fixture, receiver: fixture.receiver,
            arguments: [spell, .integer(1)]
        ) == .returned(.none))
        #expect(call(
            "Actor", "GetEquippedSpell", fixture, receiver: fixture.receiver,
            arguments: [.integer(1)], returnType: .object("Spell")
        ) == .returned(spell))
        #expect(call(
            "Actor", "GetEquippedSpell", fixture, receiver: fixture.receiver,
            arguments: [.integer(0)], returnType: .object("Spell")
        ) == .returned(.none))
    }

    @Test func unequipSpellOnlyClearsTheHandHoldingIt() throws {
        let fixture = try Self.fixture()
        let spell = spellHandle(SpellbookFixture.Spell.fastHealing, fixture)
        let other = spellHandle(SpellbookFixture.Spell.healing, fixture)
        call(
            "Actor", "EquipSpell", fixture, receiver: fixture.receiver,
            arguments: [spell, .integer(1)]
        )
        // A spell that is not in that hand leaves it alone.
        call(
            "Actor", "UnequipSpell", fixture, receiver: fixture.receiver,
            arguments: [other, .integer(1)]
        )
        #expect(call(
            "Actor", "GetEquippedSpell", fixture, receiver: fixture.receiver,
            arguments: [.integer(1)], returnType: .object("Spell")
        ) == .returned(spell))
        call(
            "Actor", "UnequipSpell", fixture, receiver: fixture.receiver,
            arguments: [spell, .integer(1)]
        )
        #expect(call(
            "Actor", "GetEquippedSpell", fixture, receiver: fixture.receiver,
            arguments: [.integer(1)], returnType: .object("Spell")
        ) == .returned(.none))
    }

    @Test func theVoiceSourceIsRefusedRatherThanSilentlyIgnored() throws {
        let fixture = try Self.fixture()
        let spell = spellHandle(SpellbookFixture.Spell.dragonskin, fixture)
        #expect(PapyrusWorldFixture.isInvalidArguments(call(
            "Actor", "EquipSpell", fixture, receiver: fixture.receiver,
            arguments: [spell, .integer(2)]
        )))
        #expect(PapyrusWorldFixture.isInvalidArguments(call(
            "Actor", "GetEquippedSpell", fixture, receiver: fixture.receiver,
            arguments: [.integer(2)], returnType: .object("Spell")
        )))
    }
}
