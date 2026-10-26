// A fake session and a synthetic two-state graph for the sub-graph coordinator tests.

import OpenSkyBehavior
import OpenSkyEngineTesting
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
@testable import OpenSkyObjectAnimation

@MainActor
final class FakeEffectWorld: EffectGraphWorld {
    var attached: [AttachedSubGraph] = []
    var characters: [ReferenceKey: SubGraphCharacter] = [:]
    var fired: [(String, ReferenceKey)] = []

    func attachedSubGraphs() -> [AttachedSubGraph] {
        attached
    }

    func character(of actor: ReferenceKey) -> SubGraphCharacter? {
        characters[actor]
    }

    func effectGraphFired(_ event: String, from actor: ReferenceKey) {
        fired.append((event, actor))
    }
}

@MainActor
enum EffectGraphFixture {
    static let caster = ReferenceKey.plugin(name: "test.esp", objectID: 0x10)
    static let other = ReferenceKey.plugin(name: "test.esp", objectID: 0x11)

    /// Two states, "Wait" and "Fire"; event 0 moves Wait to Fire.
    static func graph(
        events: [String], variables: [BehaviorVariableSpec] = []
    ) -> BehaviorGraphInstance {
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
            root: root, table: table,
            data: BehaviorFixture.graphData(variables: variables, events: events),
            clips: BehaviorFixture.staticClipPair(left: 0, right: 10)
        )
    }

    static func effect(_ id: Int, on actor: ReferenceKey) -> AttachedSubGraph {
        AttachedSubGraph(
            id: .effect(id), anchor: .actor(actor), name: "FireHand",
            modelPath: "magic\\firehand.nif"
        )
    }

    /// The coordinator holds its world weakly, so each test keeps `world` alive.
    static func running(
        _ entries: [(AttachedSubGraph, BehaviorGraphInstance)],
        world: FakeEffectWorld = FakeEffectWorld()
    ) -> (EffectGraphCoordinator, FakeEffectWorld) {
        world.attached = entries.map(\.0)
        let effects = EffectGraphCoordinator(world: world, files: { nil })
        for (attachment, instance) in entries {
            effects.start(attachment, project: "meshes\\magic\\fire.hkx", instance: instance)
        }
        effects.tick(deltaTime: 0.1)
        return (effects, world)
    }
}
