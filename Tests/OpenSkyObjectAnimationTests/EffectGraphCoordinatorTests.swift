// Effect graphs hear their actor's animation events: a synthetic graph on an effect takes
// a transition on an event the actor raised, and a graph that does not declare it does not.

@testable import OpenSkyObjectAnimation
import Testing

@MainActor
struct EffectGraphCoordinatorTests {
    private typealias Fixture = EffectGraphFixture

    @Test func anAttachedGraphTakesATransitionOnItsActorsEvent() {
        let (effects, world) = Fixture.running([
            (Fixture.effect(1, on: Fixture.caster), Fixture.graph(events: ["MLh_SpellFire_Event"]))
        ])
        defer { withExtendedLifetime(world) {} }
        #expect(effects.rows.first?.activeState == "Wait")
        effects.deliver("MLh_SpellFire_Event", from: Fixture.caster)
        effects.tick(deltaTime: 0.1)
        let row = effects.rows.first
        #expect(row?.activeState == "Fire")
        #expect(row?.lastEvent == "MLh_SpellFire_Event")
        #expect(row?.takenCount == 1)
    }

    @Test func aGraphThatDoesNotDeclareTheEventIgnoresIt() {
        let (effects, world) = Fixture.running([
            (
                Fixture.effect(1, on: Fixture.caster),
                Fixture.graph(events: ["Voice_SpellFire_Event"])
            )
        ])
        defer { withExtendedLifetime(world) {} }
        effects.deliver("MLh_SpellFire_Event", from: Fixture.caster)
        effects.tick(deltaTime: 0.1)
        #expect(effects.rows.first?.activeState == "Wait")
        #expect(effects.rows.first?.lastEvent == nil)
    }

    @Test func anotherActorsEventDoesNotReachTheEffect() {
        let (effects, world) = Fixture.running([
            (Fixture.effect(1, on: Fixture.caster), Fixture.graph(events: ["MLh_SpellFire_Event"])),
            (Fixture.effect(2, on: Fixture.other), Fixture.graph(events: ["MLh_SpellFire_Event"]))
        ])
        defer { withExtendedLifetime(world) {} }
        effects.deliver("MLh_SpellFire_Event", from: Fixture.other)
        effects.tick(deltaTime: 0.1)
        #expect(effects.rows.map(\.activeState) == ["Wait", "Fire"])
    }

    @Test func anEffectThatEndsDropsItsGraph() {
        let (effects, world) = Fixture.running([
            (Fixture.effect(1, on: Fixture.caster), Fixture.graph(events: ["MLh_SpellFire_Event"]))
        ])
        world.attached = []
        effects.tick(deltaTime: 0.1)
        #expect(effects.rows.isEmpty)
    }
}
