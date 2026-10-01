// The NPC gait clip cache over an in-memory file source. No game data.

import Foundation
import GameDataTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyWorld
import Testing

@MainActor
private final class FakeNPCAnimationWorld: NPCAnimationWorld {
    var animationFiles: (any GameFileSource)?

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

        world.animationFiles = InMemoryFileSource()
        #expect(coordinator.gaitClip(.sneak, skeletonMeshPath: Self.skeleton, female: false) == nil)
        #expect(coordinator.unresolvableClips.isEmpty, "a gait with no clip is not a failed load")
    }

    @Test func aFailedLoadIsRememberedPerSkeletonAndPath() throws {
        let world = FakeNPCAnimationWorld()
        world.animationFiles = InMemoryFileSource()
        let coordinator = NPCAnimationCoordinator()
        coordinator.attach(world: world)

        #expect(coordinator.gaitClip(.walk, skeletonMeshPath: Self.skeleton, female: false) == nil)
        #expect(coordinator.gaitClip(.run, skeletonMeshPath: Self.skeleton, female: true) == nil)
        let walk = try #require(ActorAnimationClipLoader.gaitAnimationPath(.walk, female: false))
        let run = try #require(ActorAnimationClipLoader.gaitAnimationPath(.run, female: true))
        #expect(coordinator.unresolvableClips == [
            "\(Self.skeleton)#\(walk)",
            "\(Self.skeleton)#\(run)"
        ])
    }
}
