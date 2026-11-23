// A concentration spell whose caster's graph raises spell-fire events waits for the
// event before it starts, and the cost is checked there. See
// docs/engine/spellcasting.md#casting-cues.

import Foundation
@testable import OpenSkyActors
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagic
import OpenSkyMagicFixtures
@testable import OpenSkyMagicInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct CasterSpellFireTests {
    private struct Harness {
        let runtime: CasterRuntime
        let world: FakeCasterWorld
        let values: ActorValueRuntime
        let cost: Float
    }

    private func harness() throws -> Harness {
        let store = WorldStateStore()
        let (spellbook, _) = try SpellbookFixture.runtime(store: store)
        let values = SpellbookFixture.values(store: store)
        let world = FakeCasterWorld()
        let runtime = CasterRuntime(spellbook: spellbook, values: values, world: world)
        runtime.spellFireCasters = [.player]
        let key = SpellbookFixture.key(SpellbookFixture.Spell.healing)
        spellbook.learn(key, on: .player)
        try spellbook.equip(key, in: .right, on: .player)
        let spell = try #require(spellbook.record(key))
        return Harness(runtime: runtime, world: world, values: values, cost: Float(spell.cost.cost))
    }

    @Test func aConcentrationSpellWaitsForTheSpellFireEvent() throws {
        let harness = try harness()

        harness.runtime.begin(.right, on: .player)
        harness.runtime.advance(delta: 0.1, on: .player)

        #expect(harness.runtime.phase(of: .right) == .ready)
        #expect(harness.world.applications.isEmpty)
        #expect(harness.values.current(of: .player).magicka == 100)

        let outcome = harness.runtime.fire(.right, on: .player)

        #expect(harness.runtime.phase(of: .right) == .concentrating)
        guard case .concentrating = outcome else {
            Issue.record("expected a start, got \(outcome)")
            return
        }
        #expect(harness.world.applications.count == 1)
    }

    @Test func aFailedCostCheckAtTheEventResetsTheHand() throws {
        let harness = try harness()
        harness.runtime.begin(.right, on: .player)
        harness.values.set(.magicka, to: harness.cost / 2, on: .player)

        let outcome = harness.runtime.fire(.right, on: .player)

        guard case .insufficientMagicka = outcome.failure else {
            Issue.record("expected an insufficient-magicka failure, got \(outcome)")
            return
        }
        #expect(harness.runtime.phase(of: .right) == .idle)
        #expect(harness.runtime.takePlayerFailures().count == 1)
        #expect(harness.world.applications.isEmpty)
    }

    @Test func aGraphThatRaisesNothingStartsTheSpellAfterTheWait() throws {
        let harness = try harness()
        harness.runtime.begin(.right, on: .player)

        for _ in 0 ..< 30 {
            harness.runtime.advance(delta: 1.0 / 60, on: .player)
        }

        #expect(harness.runtime.phase(of: .right) == .concentrating)
        #expect(harness.runtime.fire(.right, on: .player) == .ignored)
    }

    @Test func aReleaseBeforeTheEventStillCastsTheMinimum() throws {
        let harness = try harness()
        harness.runtime.begin(.right, on: .player)

        harness.runtime.release(.right, on: .player)

        #expect(harness.runtime.phase(of: .right) == .concentrating)
        #expect(harness.world.applications.count == 1)
        harness.runtime.advance(delta: 0.5, on: .player)
        #expect(harness.runtime.phase(of: .right) == .idle)
    }

    @Test func aCasterWithoutGraphEventsStartsAtTheEndOfTheCharge() throws {
        let harness = try harness()
        harness.runtime.spellFireCasters = []

        harness.runtime.begin(.right, on: .player)

        #expect(harness.runtime.phase(of: .right) == .concentrating)
    }

    @Test func aConcentrationHandMakesNoReadySound() {
        let view = CastingHandView(
            phase: .ready,
            spell: SpellbookFixture.key(1),
            isConcentration: true
        )

        #expect(CastingCueRule.loopKind(of: view) == nil)
    }
}
