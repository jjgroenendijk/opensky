// The dead player's body falls through the same ragdoll path as an NPC's, and a
// reload stands it up again.

@testable import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyPhysics
@testable import OpenSkyWorldState
import simd
import Testing

@MainActor
struct RagdollPlayerFallTests {
    private static func coordinator(world: FakeRagdollSessionWorld) -> RagdollCoordinator {
        world.playerHasBody = true
        return RagdollCoordinator(
            store: WorldStateStore(),
            world: world,
            data: RagdollSessionData(loadDefinition: { _, _, _ in
                RagdollFixture.limb().definition
            })
        )
    }

    private static func playerBones(_ commands: [RagdollCommand]) -> [String: float4x4]? {
        for case let .publishPlayerRagdoll(bones) in commands {
            return bones
        }
        return nil
    }

    @Test
    func withoutAGraphThePlayerFallsAtOnceAndWritesNoDeath() throws {
        let world = FakeRagdollSessionWorld()
        let coordinator = Self.coordinator(world: world)
        coordinator.dropPlayerBody()
        let runtime = try #require(coordinator.runtime)
        #expect(runtime.world.isRagdolling(.player))
        #expect(runtime.fallbackDeathCount == 1)
        #expect(coordinator.deathState(of: .player) == nil)
        let commands = coordinator.publishPoses()
        #expect(Self.playerBones(commands)?.isEmpty == false)
        for case let .publishPoses(poses) in commands {
            #expect(poses.isEmpty, "the player's bones went to the cell's actors")
        }
    }

    @Test
    func aGraphThatTakesTheDeathEventsHandsOffOnItsCue() throws {
        let world = FakeRagdollSessionWorld()
        world.declaredPlayerEvents = Set(RagdollGraphNames.deathEvents)
        let coordinator = Self.coordinator(world: world)
        coordinator.dropPlayerBody()
        let runtime = try #require(coordinator.runtime)
        #expect(!runtime.world.isRagdolling(.player))
        #expect(runtime.pendingHandOffs.contains(.player))
        _ = coordinator.advance(
            events: ["AddRagdollToWorld"], controls: RagdollGraphControls(), delta: 1 / 60
        )
        #expect(runtime.world.isRagdolling(.player))
    }

    @Test
    func aReloadStandsThePlayerUpAndClearsTheBodyOnce() throws {
        let world = FakeRagdollSessionWorld()
        let coordinator = Self.coordinator(world: world)
        coordinator.dropPlayerBody()
        _ = coordinator.publishPoses()
        coordinator.resetPlayerDeath()
        let runtime = try #require(coordinator.runtime)
        #expect(!runtime.world.isRagdolling(.player))
        #expect(coordinator.playerDeath.phase == .alive)
        #expect(Self.playerBones(coordinator.publishPoses())?.isEmpty == true)
        #expect(Self.playerBones(coordinator.publishPoses()) == nil)
    }
}
