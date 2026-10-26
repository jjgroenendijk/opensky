// Sub-graphs read their actor as the game runs them: shared variables, a script's
// sub-graph event and variable, an effect at a point, and a worn armour addon.

import OpenSkyActorPresentation
import OpenSkyBehavior
import OpenSkyEngineTesting
import OpenSkyFormatsAnimation
@testable import OpenSkyObjectAnimation
import simd
import Testing

@MainActor
struct EffectGraphSubGraphTests {
    private typealias Fixture = EffectGraphFixture

    private static func actorVariables(speed: Float) -> BehaviorVariableStore {
        BehaviorVariableStore(data: BehaviorFixture.graphData(variables: [
            BehaviorVariableSpec("Speed", .real, speed),
            BehaviorVariableSpec("iActorOnly", .int32, 4)
        ]))
    }

    private static func character(speed: Float, at feet: SIMD3<Float>) -> SubGraphCharacter {
        SubGraphCharacter(
            context: BehaviorCharacterContext(worldPosition: feet),
            variables: actorVariables(speed: speed)
        )
    }

    private static func speed(_ effects: EffectGraphCoordinator, _ id: SubGraphID) -> Float? {
        effects.running[id]?.instance.variable(named: "Speed")?.realValue
    }

    @Test func aSubGraphReadsItsActorsVariablesAndPlacement() {
        let world = FakeEffectWorld()
        world.characters[Fixture.caster] = Self.character(speed: 250, at: SIMD3(1, 2, 3))
        let graph = Fixture.graph(events: [], variables: [BehaviorVariableSpec("Speed", .real, 0)])
        let (effects, _) = Fixture.running(
            [(Fixture.effect(1, on: Fixture.caster), graph)],
            world: world
        )
        #expect(Self.speed(effects, .effect(1)) == 250)
        #expect(graph.characterContext.worldPosition == SIMD3(1, 2, 3))
        #expect(graph.variable(named: "iActorOnly") == nil)
    }

    @Test func scriptSubGraphCallsReachEveryGraphOnTheActor() {
        let world = FakeEffectWorld()
        world.characters[Fixture.caster] = Self.character(speed: 250, at: .zero)
        let spec = [BehaviorVariableSpec("Speed", .real, 0)]
        let (effects, _) = Fixture.running([
            (
                Fixture.effect(1, on: Fixture.caster),
                Fixture.graph(events: ["Start"], variables: spec)
            ),
            (
                Fixture.effect(2, on: Fixture.other),
                Fixture.graph(events: ["Start"], variables: spec)
            )
        ], world: world)
        #expect(effects.deliver("Start", from: Fixture.caster))
        #expect(effects.setSubGraphVariable(7, named: "speed", on: Fixture.caster))
        #expect(!effects.setSubGraphVariable(7, named: "fMissing", on: Fixture.caster))
        effects.tick(deltaTime: 0.1)
        #expect(effects.rows.map(\.activeState) == ["Fire", "Wait"])
        // The script's value holds; the actor's own value no longer overwrites it.
        #expect(Self.speed(effects, .effect(1)) == 7)
        #expect(Self.speed(effects, .effect(2)) == 0)
    }

    @Test func anEffectAtAPointRunsItsGraphAndHearsNoActor() {
        let point = AttachedSubGraph(
            id: .effect(3), anchor: .point(SIMD3(10, 0, 0)), name: "Explosion",
            modelPath: "magic\\fireballexplosion.nif"
        )
        let graph = Fixture.graph(events: ["Start"])
        let (effects, world) = Fixture.running([(point, graph)])
        effects.deliver("Start", from: Fixture.caster)
        effects.tick(deltaTime: 0.1)
        #expect(effects.rows.first?.actor == nil)
        #expect(effects.rows.first?.activeState == "Wait")
        #expect(graph.characterContext.worldPosition == SIMD3(10, 0, 0))
        #expect(world.fired.isEmpty)
    }

    @Test func aWornArmorAddonRunsAsASubGraph() {
        let addon = AttachedSubGraph(
            id: .armorAddon(Fixture.caster, armature: 0x1234), anchor: .actor(Fixture.caster),
            name: "armor\\cloak.nif", modelPath: "armor\\cloak.nif"
        )
        let (effects, world) = Fixture.running([(addon, Fixture.graph(events: ["Start"]))])
        defer { withExtendedLifetime(world) {} }
        #expect(effects.hasSubGraphs(on: Fixture.caster))
        effects.deliver("Start", from: Fixture.caster)
        effects.tick(deltaTime: 0.1)
        #expect(effects.rows.first?.id == .armorAddon(Fixture.caster, armature: 0x1234))
        #expect(effects.rows.first?.activeState == "Fire")
    }
}

@MainActor
struct EffectGraphArmorAddonPoseTests {
    private typealias Fixture = EffectGraphFixture
    private static let rest = HKABonePose(
        translation: .zero, rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), scale: .one
    )

    private static func skeleton(_ names: [String], parents: [Int]) -> BehaviorSkeleton {
        BehaviorSkeleton(
            referencePose: names.map { _ in Self.rest },
            parentIndices: parents, boneNames: names
        )
    }

    @Test func onlyBonesWhoseParentAlsoMatchesAreMapped() {
        let graph = Self.skeleton(["NPC Pelvis", "TailBone01", "Loose"], parents: [-1, 0, -1])
        let actor = Self.skeleton(
            ["NPC Root", "NPC Pelvis", "TAILBONE01", "Loose"], parents: [-1, 0, 1, 0]
        )
        let map = SubGraphBoneMap(graph: graph, actor: actor)
        #expect(map.pairs.map(\.graph) == [1])
        #expect(map.pairs.map(\.actor) == [2])
    }

    @Test func anAddonGraphsBonesReachItsActorsPoseUntilItEnds() {
        let pose = PlayerPoseBuffer()
        pose.publish([Self.rest, Self.rest])
        let world = FakeEffectWorld()
        let effects = EffectGraphCoordinator(world: world, files: { nil })
        let addon = AttachedSubGraph(
            id: .armorAddon(Fixture.caster, armature: 1), anchor: .actor(Fixture.caster),
            name: "tail", modelPath: "tail.nif"
        )
        effects.start(addon, project: "tail.hkx", instance: Fixture.graph(events: []))
        let entry = effects.running[addon.id]
        let names = ["NPC Pelvis", "TailBone01"]
        entry?.actorRig = SubGraphActorRig(
            skeleton: Self.skeleton(names, parents: [-1, 0]), pose: pose
        )
        entry?.boneMap = SubGraphBoneMap(
            graph: Self.skeleton(names, parents: [-1, 0]),
            actor: Self.skeleton(names, parents: [-1, 0])
        )
        let moved = HKABonePose(
            translation: SIMD3(0, 5, 0),
            rotation: Self.rest.rotation,
            scale: .one
        )
        entry?.bones = [Self.rest, moved]
        effects.poseArmorAddons()
        #expect(pose.bones.last?.translation == SIMD3(0, 5, 0))
        pose.publish([Self.rest, Self.rest])
        #expect(pose.bones.last?.translation == SIMD3(0, 5, 0))
        // The addon comes off: its graph ends and the actor's own pose returns.
        effects.tick(deltaTime: 0.1)
        pose.publish([Self.rest, Self.rest])
        #expect(pose.bones.last?.translation == Self.rest.translation)
    }
}
