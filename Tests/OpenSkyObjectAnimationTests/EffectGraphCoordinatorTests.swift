// Effect graphs hear their actor's animation events: a synthetic graph on an effect takes
// a transition on an event the actor raised, and a graph that does not declare it does not.

import OpenSkyBehavior
import OpenSkyEngineTesting
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
@testable import OpenSkyObjectAnimation
import Testing

@MainActor
private final class FakeEffectWorld: EffectGraphWorld {
    var attached: [AttachedEffectModel] = []
    var fired: [(String, ReferenceKey)] = []

    func attachedEffectModels() -> [AttachedEffectModel] {
        attached
    }

    func effectGraphFired(_ event: String, from actor: ReferenceKey) {
        fired.append((event, actor))
    }
}

@MainActor
struct EffectGraphCoordinatorTests {
    private static let caster = ReferenceKey.plugin(name: "test.esp", objectID: 0x10)
    private static let other = ReferenceKey.plugin(name: "test.esp", objectID: 0x11)

    /// Two states, "Wait" and "Fire"; event 0 moves Wait to Fire.
    private static func graph(events: [String]) -> BehaviorGraphInstance {
        var table = BehaviorObjectTable()
        let wait = table.add(
            BehaviorFixture.clipGenerator("wait", animationName: "left"),
            at: 0x100
        )
        let fire = table.add(
            BehaviorFixture.clipGenerator("fire", animationName: "right"),
            at: 0x110
        )
        let transitions = table.add(
            BehaviorStateMachineFixture.transitions([BehaviorTransitionSpec(
                eventId: 0,
                toStateId: 1
            )]),
            at: 0x200
        )
        let waitState = table.add(
            BehaviorStateMachineFixture.stateInfo(BehaviorStateSpec(
                stateId: 0, name: "Wait", generator: wait, transitions: transitions
            )),
            at: 0x300
        )
        let fireState = table.add(
            BehaviorStateMachineFixture.stateInfo(BehaviorStateSpec(
                stateId: 1, name: "Fire", generator: fire
            )),
            at: 0x310
        )
        let root = table.add(
            BehaviorStateMachineFixture.machine("effect", states: [waitState, fireState]),
            at: 0x400
        )
        return BehaviorFixture.instance(
            root: root, table: table, data: BehaviorFixture.graphData(events: events),
            clips: BehaviorFixture.staticClipPair(left: 0, right: 10)
        )
    }

    private static func attachment(_ id: Int, on actor: ReferenceKey) -> AttachedEffectModel {
        AttachedEffectModel(
            effectID: id, actor: actor, effectName: "FireHand", modelPath: "magic\\firehand.nif"
        )
    }

    /// The coordinator holds its world weakly, so each test keeps `world` alive.
    private func running(
        _ entries: [(AttachedEffectModel, BehaviorGraphInstance)]
    ) -> (EffectGraphCoordinator, FakeEffectWorld) {
        let world = FakeEffectWorld()
        world.attached = entries.map(\.0)
        let effects = EffectGraphCoordinator(world: world, files: { nil })
        for (attachment, instance) in entries {
            effects.start(attachment, project: "meshes\\magic\\fire.hkx", instance: instance)
        }
        effects.tick(deltaTime: 0.1)
        return (effects, world)
    }

    @Test func anAttachedGraphTakesATransitionOnItsActorsEvent() {
        let (effects, world) = running([
            (Self.attachment(1, on: Self.caster), Self.graph(events: ["MLh_SpellFire_Event"]))
        ])
        defer { withExtendedLifetime(world) {} }
        #expect(effects.rows.first?.activeState == "Wait")
        effects.deliver("MLh_SpellFire_Event", from: Self.caster)
        effects.tick(deltaTime: 0.1)
        let row = effects.rows.first
        #expect(row?.activeState == "Fire")
        #expect(row?.lastEvent == "MLh_SpellFire_Event")
        #expect(row?.takenCount == 1)
    }

    @Test func aGraphThatDoesNotDeclareTheEventIgnoresIt() {
        let (effects, world) = running([
            (Self.attachment(1, on: Self.caster), Self.graph(events: ["Voice_SpellFire_Event"]))
        ])
        defer { withExtendedLifetime(world) {} }
        effects.deliver("MLh_SpellFire_Event", from: Self.caster)
        effects.tick(deltaTime: 0.1)
        #expect(effects.rows.first?.activeState == "Wait")
        #expect(effects.rows.first?.lastEvent == nil)
    }

    @Test func anotherActorsEventDoesNotReachTheEffect() {
        let (effects, world) = running([
            (Self.attachment(1, on: Self.caster), Self.graph(events: ["MLh_SpellFire_Event"])),
            (Self.attachment(2, on: Self.other), Self.graph(events: ["MLh_SpellFire_Event"]))
        ])
        defer { withExtendedLifetime(world) {} }
        effects.deliver("MLh_SpellFire_Event", from: Self.other)
        effects.tick(deltaTime: 0.1)
        #expect(effects.rows.map(\.activeState) == ["Wait", "Fire"])
    }

    @Test func anEffectThatEndsDropsItsGraph() {
        let (effects, world) = running([
            (Self.attachment(1, on: Self.caster), Self.graph(events: ["MLh_SpellFire_Event"]))
        ])
        world.attached = []
        effects.tick(deltaTime: 0.1)
        #expect(effects.rows.isEmpty)
    }
}
