// Dual casting: the same spell begun in both hands casts once, for 2.8 times the
// cost and 2.2 times the power, and only with a `Can Dual Cast Spell` perk.

import Foundation
@testable import OpenSkyActors
import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagic
import OpenSkyMagicFixtures
@testable import OpenSkyMagicInterface
@testable import OpenSkyProgression
@testable import OpenSkyWorldState
import Testing

@MainActor
struct DualCastTests {
    private struct Harness {
        let runtime: CasterRuntime
        let world: FakeCasterWorld
        let values: ActorValueRuntime
    }

    private func harness(dualCastPerk: Bool) throws -> Harness {
        let store = WorldStateStore()
        let index = try PerkRuntimeFixture.index()
        let spellbook = SpellbookRuntime(
            store: store,
            spells: PerkRuntimeFixture.spellStore(index: index),
            equipSlots: EquipSlotStore(index: index)
        )
        let values = PerkRuntimeFixture.values(store: store)
        let world = FakeCasterWorld()
        let runtime = CasterRuntime(spellbook: spellbook, values: values, world: world)
        var (perks, _) = try PerkRuntimeFixture.runtime(store: store)
        if dualCastPerk {
            perks.add(PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.dualCasting), to: .player)
        }
        runtime.perks = perks
        let key = PerkRuntimeFixture.key(PerkRuntimeFixture.Spell.dualCastable)
        spellbook.learn(key, on: .player)
        // The fixture plugin has no EQUP records, so the hands are filled directly.
        store.set(
            spellbook.state(of: .player).equipping(key, in: [.leftHand, .rightHand]),
            for: .player, in: nil
        )
        return Harness(runtime: runtime, world: world, values: values)
    }

    private func magicka(_ harness: Harness) -> Float {
        harness.values.current(of: .player).magicka
    }

    @Test func withoutThePerkBothHandsCastTwoSingleSpells() throws {
        let harness = try harness(dualCastPerk: false)
        harness.runtime.begin(.right, on: .player)
        harness.runtime.begin(.left, on: .player)
        #expect(!harness.runtime.state(of: .right).isDualCast)

        harness.runtime.release(.right, on: .player)
        harness.runtime.release(.left, on: .player)
        #expect(harness.world.applications.count == 2)
        #expect(magicka(harness) == 80)
        #expect(harness.world.appliedEntries.first?.first?.magnitude == 10)
    }

    @Test func withThePerkBothHandsCastOneStrongerSpell() throws {
        let harness = try harness(dualCastPerk: true)
        harness.runtime.begin(.right, on: .player)
        harness.runtime.begin(.left, on: .player)
        #expect(harness.runtime.state(of: .right).dualRole == .lead)
        #expect(harness.runtime.state(of: .left).dualRole == .partner)
        #expect(harness.runtime.tally.dualCastCount == 1)

        let outcome = harness.runtime.release(.left, on: .player)
        guard case let .cast(result) = outcome else {
            Issue.record("expected a cast, got \(outcome)")
            return
        }
        #expect(result.isDualCast)
        #expect(abs(result.magickaSpent - 28) < 0.001)
        #expect(harness.world.applications.count == 1)
        let entry = try #require(harness.world.appliedEntries.first?.first)
        #expect(abs(entry.magnitude - 22) < 0.001)
        #expect(entry.duration == 66)
        #expect(harness.runtime.phase(of: .left) == .idle)
        #expect(harness.runtime.phase(of: .right) == .idle)
    }

    @Test func aSecondHandBegunLateCastsAlone() throws {
        let harness = try harness(dualCastPerk: true)
        harness.runtime.begin(.right, on: .player)
        harness.runtime.advance(delta: 1, on: .player)
        harness.runtime.begin(.left, on: .player)
        #expect(!harness.runtime.state(of: .left).isDualCast)
    }

    @Test func dualCastEffectsAnswerEffectWasDualCast() {
        var context = ConditionContext()
        context.magicApplication = MagicApplicationContext(isDualCast: true)
        #expect(context.magicApplication.isDualCast)
        let payload = SpellPayload(
            spell: .player, sourcePlugin: "", caster: .player, entries: [],
            isHostile: false, ignoresResistance: false, projectile: nil, name: "x"
        ).dualCast([])
        #expect(payload.isDualCast)
    }
}
