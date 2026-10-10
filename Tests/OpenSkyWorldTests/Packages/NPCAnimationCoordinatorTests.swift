// The NPC gait clip cache over an in-memory file source. No game data.

import Foundation
import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyWorld
import Testing

@MainActor
private final class FakeNPCAnimationWorld: NPCAnimationWorld {
    var animationClips: ActorClipLoader?

    func useFiles(_ files: any GameFileSource) {
        animationClips = ActorClipLoader(
            worker: ImmediateAssetLoadWorker(load: ActorClipLoader.load(files: files))
        )
    }

    func actorPlayback(for _: ReferenceKey) -> ActorAnimationPlayback? {
        nil
    }
}

@MainActor
struct NPCAnimationCoordinatorTests {
    private static let skeleton = ActorAnimationClipLoader.characterRoot
        + "character assets\\skeleton.nif"

    @Test func noClipWithoutGameDataOrForAGaitWithoutOne() {
        let world = FakeNPCAnimationWorld()
        let coordinator = NPCAnimationCoordinator()
        coordinator.attach(world: world)
        #expect(coordinator.gaitClip(.walk, skeletonMeshPath: Self.skeleton, female: false) == nil)

        world.useFiles(InMemoryFileSource())
        #expect(coordinator.gaitClip(.sneak, skeletonMeshPath: Self.skeleton, female: false) == nil)
        #expect(coordinator.unresolvableClips.isEmpty, "a gait with no clip is not a failed load")
    }

    @Test func aFailedLoadIsRememberedPerSkeletonAndPath() throws {
        let world = FakeNPCAnimationWorld()
        world.useFiles(InMemoryFileSource())
        let coordinator = NPCAnimationCoordinator()
        coordinator.attach(world: world)

        #expect(coordinator.gaitClip(.walk, skeletonMeshPath: Self.skeleton, female: false) == nil)
        #expect(coordinator.gaitClip(.run, skeletonMeshPath: Self.skeleton, female: true) == nil)
        #expect(coordinator.unresolvableClips.isEmpty, "a failure shows after the drain")
        world.animationClips?.drain()
        _ = coordinator.gaitClip(.walk, skeletonMeshPath: Self.skeleton, female: false)
        _ = coordinator.gaitClip(.run, skeletonMeshPath: Self.skeleton, female: true)
        #expect(world.animationClips?.pendingCount == 0, "a failure is not requested again")
        let walk = try #require(ActorAnimationClipLoader.gaitAnimationPath(.walk, female: false))
        let run = try #require(ActorAnimationClipLoader.gaitAnimationPath(.run, female: true))
        #expect(coordinator.unresolvableClips == [
            "\(Self.skeleton)#\(walk)",
            "\(Self.skeleton)#\(run)"
        ])
    }

    @Test func aRiderPlaysTheRiderClipsOfItsHorse() {
        #expect(ActorAnimationClipLoader.riderAnimationPath(nil)
            == ActorAnimationClipLoader.characterRoot + "animations\\horse_rider\\idle.hkx")
        #expect(ActorAnimationClipLoader.riderAnimationPath(.run)
            == ActorAnimationClipLoader.characterRoot + "animations\\horse_rider\\runforward.hkx")
        let coordinator = NPCAnimationCoordinator()
        coordinator.attach(world: FakeNPCAnimationWorld())
        let rider = ReferenceKey.plugin(name: "ride.esm", objectID: 1)
        let horse = ReferenceKey.plugin(name: "ride.esm", objectID: 2)
        coordinator.ride(rider, on: horse)
        #expect(coordinator.riders == [horse: rider])
        coordinator.dismount(rider)
        #expect(coordinator.riders.isEmpty)
    }
}
