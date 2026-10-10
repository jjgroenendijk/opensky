// Clip paths per skeleton: a character's clips are gendered with an `mt_` prefix,
// a creature's sit beside its own skeleton.

import OpenSkyPhysics
@testable import OpenSkyWorld
import Testing

struct ActorAnimationClipPathTests {
    private static let horse = "meshes\\actors\\horse\\character assets\\skeleton.nif"
    private static let character = "meshes\\actors\\character\\character assets\\skeleton.nif"

    @Test func aCreatureUsesClipsBesideItsSkeleton() {
        #expect(ActorAnimationClipLoader.idleAnimationPath(
            skeletonMeshPath: Self.horse,
            female: false
        )
            == "meshes\\actors\\horse\\animations\\idle.hkx")
        #expect(ActorAnimationClipLoader.gaitAnimationPath(
            .walk,
            skeletonMeshPath: Self.horse,
            female: false
        )
            == "meshes\\actors\\horse\\animations\\walkforward.hkx")
        #expect(ActorAnimationClipLoader.gaitAnimationPath(
            .sneak,
            skeletonMeshPath: Self.horse,
            female: false
        )
            == nil)
    }

    @Test func aCharacterKeepsItsGenderedClips() {
        #expect(ActorAnimationClipLoader.idleAnimationPath(
            skeletonMeshPath: Self.character,
            female: true
        )
            == ActorAnimationClipLoader.idleAnimationPath(female: true))
        #expect(ActorAnimationClipLoader.gaitAnimationPath(
            .run,
            skeletonMeshPath: Self.character,
            female: false
        )
            == "meshes\\actors\\character\\animations\\male\\mt_runforward.hkx")
        #expect(ActorAnimationClipLoader.creatureRoot("meshes\\clutter\\cart.nif") == nil)
    }
}
