// An NPC that stops keeps drawing where it stopped through its draw delta, until
// its cell is built with the saved pose.

@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import simd
import Testing

extension NPCMovementRuntimeTests {
    /// An arrived actor keeps drawing where it stopped until its cell's build bakes
    /// the pose in, so its arrival needs no rebuild.
    @Test
    func arrivedActorKeepsItsDrawDeltaUntilBaked() throws {
        var runtime = NPCMovementRuntime()
        let target = SIMD3<Float>(100, 0, 0)
        let started = runtime.start(Self.start(
            actor: actor, path: Self.path(waypoints: [target], target: target)
        ))
        #expect(started)
        for _ in 0 ..< 40 where runtime.activeMoverCount > 0 {
            runtime.advance(by: 0.1, world: Self.world())
        }
        #expect(runtime.activeMoverCount == 0)
        let resting = try #require(runtime.transform(for: actor))
        let parkedDelta = try #require(runtime.instanceDeltas()[1])
        #expect(abs(parkedDelta.columns.3.x - resting.position.x) < 0.01)
        #expect(resting.position.x > 80)

        runtime.bake(actor, at: resting.placement)
        let baked = try #require(runtime.instanceDeltas()[1])
        #expect(simd_distance(baked.columns.3, SIMD4(0, 0, 0, 1)) < 0.001)
    }

    /// A walk that starts before the rebuild measures its delta from the pose the
    /// build drew, not from where the actor now stands.
    @Test
    func secondWalkMeasuresFromTheDrawnPose() throws {
        var runtime = NPCMovementRuntime()
        let first = SIMD3<Float>(100, 0, 0)
        let startedFirst = runtime.start(Self.start(
            actor: actor, path: Self.path(waypoints: [first], target: first)
        ))
        #expect(startedFirst)
        for _ in 0 ..< 40 where runtime.activeMoverCount > 0 {
            runtime.advance(by: 0.1, world: Self.world())
        }
        let resting = try #require(runtime.transform(for: actor))
        let second = resting.position + SIMD3(0, 100, 0)
        let startedSecond = runtime.start(NPCMoveStart(
            actor: actor,
            formID: FormID(1),
            placement: resting.placement,
            scale: 1,
            capsule: .standard,
            configuration: .synthetic,
            path: Self.path(waypoints: [second], target: second)
        ))
        #expect(startedSecond)
        let delta = try #require(runtime.instanceDeltas()[1])
        #expect(abs(delta.columns.3.x - resting.position.x) < 0.01)
    }
}
