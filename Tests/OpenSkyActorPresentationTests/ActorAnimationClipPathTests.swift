// Clip paths per skeleton: a character's clips are gendered with an `mt_` prefix,
// a creature's sit beside its own skeleton under one of several names.

@testable import OpenSkyActorPresentation
import OpenSkyPhysics
import Testing

struct ActorAnimationClipPathTests {
    private static let horse = "meshes\\actors\\horse\\character assets\\skeleton.nif"
    private static let wolf = "meshes\\actors\\canine\\character assets wolf\\skeleton.nif"
    private static let netch = "meshes\\actors\\dlc02\\netch\\characterassets\\skeleton.nif"
    private static let character = "meshes\\actors\\character\\character assets\\skeleton.nif"

    @Test func aCreatureTriesClipsBesideItsSkeleton() {
        let idle = ActorAnimationClipLoader.idleAnimationPaths(
            skeletonMeshPath: Self.horse, female: false
        )
        #expect(idle.first == "meshes\\actors\\horse\\animations\\idle.hkx")
        #expect(idle.contains("meshes\\actors\\horse\\animations\\mt_idle.hkx"))
        let walk = ActorAnimationClipLoader.gaitAnimationPaths(
            .walk, skeletonMeshPath: Self.horse, female: false
        )
        #expect(walk.first == "meshes\\actors\\horse\\animations\\walkforward.hkx")
        #expect(ActorAnimationClipLoader.gaitAnimationPaths(
            .sneak, skeletonMeshPath: Self.horse, female: false
        ).isEmpty)
    }

    @Test func aVariantFolderTriesItsOwnClipFirst() {
        let idle = ActorAnimationClipLoader.idleAnimationPaths(
            skeletonMeshPath: Self.wolf, female: false
        )
        let wolfIdle = idle.firstIndex(of: "meshes\\actors\\canine\\animations\\mt_idle_wolf.hkx")
        let sharedIdle = idle.firstIndex(of: "meshes\\actors\\canine\\animations\\mt_idle.hkx")
        #expect(wolfIdle != nil && sharedIdle != nil)
        #expect((wolfIdle ?? 0) < (sharedIdle ?? 0))
        #expect(CreatureClipNames.location(skeletonMeshPath: Self.netch)
            == .init(root: "meshes\\actors\\dlc02\\netch\\", variant: nil))
    }

    @Test func aGaitFallsBackToTheOtherGait() {
        let run = ActorAnimationClipLoader.gaitAnimationPaths(
            .run, skeletonMeshPath: Self.netch, female: false
        )
        let walk = ActorAnimationClipLoader.gaitAnimationPaths(
            .walk, skeletonMeshPath: Self.netch, female: false
        )
        let netchRun = "meshes\\actors\\dlc02\\netch\\animations\\netch_runforward.hkx"
        #expect(run.contains(netchRun) && walk.contains(netchRun))
        #expect(run.first == "meshes\\actors\\dlc02\\netch\\animations\\runforward.hkx")
    }

    @Test func theFirstExistingCandidateLoads() {
        let paths = ["a\\missing.hkx", "a\\present.hkx", "a\\later.hkx"]
        #expect(ActorAnimationClipLoader.chosenPath(paths) { $0 != "a\\missing.hkx" }
            == "a\\present.hkx")
        #expect(ActorAnimationClipLoader.chosenPath(paths) { _ in false } == "a\\missing.hkx")
        #expect(ActorAnimationClipLoader.chosenPath([]) { _ in true } == nil)
    }

    @Test func aCharacterKeepsItsGenderedClips() {
        #expect(ActorAnimationClipLoader.idleAnimationPaths(
            skeletonMeshPath: Self.character, female: true
        )
            == [ActorAnimationClipLoader.idleAnimationPath(female: true)])
        #expect(ActorAnimationClipLoader.gaitAnimationPaths(
            .run, skeletonMeshPath: Self.character, female: false
        )
            == ["meshes\\actors\\character\\animations\\male\\mt_runforward.hkx"])
        #expect(CreatureClipNames.location(skeletonMeshPath: "meshes\\clutter\\cart.nif") == nil)
        #expect(CreatureClipNames.location(skeletonMeshPath: Self.character) == nil)
    }
}
