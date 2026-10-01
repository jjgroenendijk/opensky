// The ragdoll shell against a fake world: the death sweep, the definition
// cache, pose publishing, the panel trigger, and the corpse search.

@testable import OpenSkyActorsInterface
@testable import OpenSkyCombat
@testable import OpenSkyFormatsAnimation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyWorldState
import PhysicsTesting
import simd
import Testing

@MainActor
struct RagdollCoordinatorTests {
    private static let near = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x101)
    private static let far = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x102)

    /// The loader counts its calls and returns the fixture limb.
    private final class Loader {
        var calls = 0
        var resolves = true

        func load(_: String, _: HKASkeleton, _: Float) -> RagdollDefinition? {
            calls += 1
            return resolves ? RagdollFixture.limb().definition : nil
        }
    }

    private struct Session {
        let coordinator: RagdollCoordinator
        let world: FakeRagdollSessionWorld
        let loader: Loader
    }

    private static func session(residents: [ReferenceKey] = [near, far]) -> Session {
        let world = FakeRagdollSessionWorld()
        world.ragdollResidents = residents.enumerated().map { index, key in
            RagdollResident(key: key, position: SIMD3(Float(index + 1) * 100, 0, 0))
        }
        let loader = Loader()
        let coordinator = RagdollCoordinator(store: WorldStateStore())
        coordinator.attach(world: world)
        coordinator.wire(loadDefinition: loader.load)
        return Session(coordinator: coordinator, world: world, loader: loader)
    }

    @Test
    func aZeroHealthActorDiesOnceAndIsReportedOnce() throws {
        let session = Self.session()
        let coordinator = session.coordinator
        let world = session.world
        world.zeroHealth = [Self.far]
        coordinator.advance(events: [], blendDuration: nil, delta: 1 / 60)
        coordinator.advance(events: [], blendDuration: nil, delta: 1 / 60)
        #expect(world.murders == [Self.far])
        #expect(coordinator.deathState(of: Self.far)?.isDead == true)
        #expect(coordinator.deathState(of: Self.near) == nil)
        let runtime = try #require(coordinator.runtime)
        #expect(runtime.deathEventsQueued == 2)
        #expect(runtime.fallbackDeathCount == 1)
    }

    @Test
    func theBlendFallsBackToTheVanillaDuration() throws {
        let session = Self.session()
        let coordinator = session.coordinator
        coordinator.advance(events: [], blendDuration: 0.25, delta: 0)
        #expect(try #require(coordinator.runtime).blendDuration == 0.25)
        coordinator.advance(events: [], blendDuration: nil, delta: 0)
        #expect(
            try #require(coordinator.runtime).blendDuration
                == HKBRigidBodyRagdollControlsModifier.vanillaBlendDuration
        )
    }

    @Test
    func oneSkeletonAndScaleIsDecodedOnce() {
        let session = Self.session()
        let coordinator = session.coordinator
        let world = session.world
        let loader = session.loader
        #expect(coordinator.ragdollActor(for: Self.near) != nil)
        #expect(coordinator.ragdollActor(for: Self.far) != nil)
        #expect(loader.calls == 1)
        world.scale = 2
        #expect(coordinator.ragdollActor(for: Self.near) != nil)
        #expect(loader.calls == 2)
    }

    @Test
    func anUnresolvableSkeletonIsNotDecodedAgain() {
        let session = Self.session()
        let coordinator = session.coordinator
        let world = session.world
        let loader = session.loader
        loader.resolves = false
        #expect(coordinator.ragdollActor(for: Self.near) == nil)
        #expect(coordinator.ragdollActor(for: Self.near) == nil)
        #expect(loader.calls == 1)
        world.skeletonMeshPath = ""
        #expect(coordinator.ragdollActor(for: Self.near) == nil)
        #expect(loader.calls == 1)
    }

    @Test
    func onlyThePlayerGraphTakesRagdollEvents() {
        let session = Self.session()
        let coordinator = session.coordinator
        let world = session.world
        world.declaredPlayerEvents = ["Death"]
        #expect(coordinator.raiseRagdollEvent("Death", on: .player))
        #expect(!coordinator.raiseRagdollEvent("Death", on: Self.near))
    }

    @Test
    func aTriggeredRagdollPublishesItsPoseAndClearDropsIt() {
        let session = Self.session()
        let coordinator = session.coordinator
        let world = session.world
        #expect(!coordinator.triggerRagdoll())
        world.selectedRagdollActor = Self.near
        #expect(coordinator.triggerRagdoll())
        coordinator.publishPoses()
        let reference = FakeRagdollSessionWorld.reference(of: Self.near).rawValue
        #expect(world.publishedRagdollPoses.keys.sorted() == [reference])
        #expect(coordinator.ragdollStatsSnapshot.ragdollCount == 1)
        coordinator.clearRagdolls()
        #expect(world.publishedRagdollPoses.isEmpty)
        #expect(coordinator.ragdollStatsSnapshot.ragdollCount == 0)
        #expect(coordinator.deathState(of: Self.near)?.isDead == true)
    }

    @Test
    func thePanelSwitchesReachTheRuntime() throws {
        let session = Self.session()
        let coordinator = session.coordinator
        coordinator.setRagdollFrozen(true)
        coordinator.setRagdollSelfCollision(false)
        let runtime = try #require(coordinator.runtime)
        #expect(runtime.isFrozen)
        #expect(!runtime.isSelfCollisionEnabled)
    }

    @Test
    func theNearestCorpseIsSearchedAndMarkedLooted() {
        let session = Self.session()
        let coordinator = session.coordinator
        let world = session.world
        #expect(!coordinator.searchNearestCorpse())
        world.selectedRagdollActor = Self.far
        coordinator.triggerRagdoll()
        world.selectedRagdollActor = Self.near
        coordinator.triggerRagdoll()
        #expect(coordinator.searchNearestCorpse())
        #expect(world.searchedCorpses == [Self.near])
        #expect(coordinator.deathState(of: Self.near)?.wasLooted == true)
        #expect(coordinator.deathState(of: Self.far)?.wasLooted == false)
    }

    @Test
    func aRefusedSearchLeavesTheCorpseUnlooted() {
        let session = Self.session(residents: [Self.near])
        let coordinator = session.coordinator
        let world = session.world
        world.selectedRagdollActor = Self.near
        coordinator.triggerRagdoll()
        world.acceptsCorpseSearch = false
        #expect(!coordinator.searchNearestCorpse())
        #expect(coordinator.deathState(of: Self.near)?.wasLooted == false)
        world.playerFeetPosition = nil
        world.acceptsCorpseSearch = true
        #expect(!coordinator.searchNearestCorpse())
    }
}
