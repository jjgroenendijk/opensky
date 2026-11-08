// BehaviorGapSweep: which behavior files share a skeleton, over archive-style paths,
// and which classes count as graph nodes.

import Foundation
@testable import OpenSkyBehavior
import Testing

struct BehaviorGapSweepTests {
    @Test func matchesEachBehaviorsFolderToTheSkeletonWithItsSuffix() {
        let sets = BehaviorGapSweep.fileSets(in: [
            "meshes\\actors\\canine\\behaviors\\dog.hkx",
            "meshes\\actors\\canine\\behaviors wolf\\wolf.hkx",
            "meshes\\actors\\canine\\character assets dog\\skeleton.hkx",
            "meshes\\actors\\canine\\character assets wolf\\skeleton.hkx",
            "meshes\\actors\\canine\\animations\\run.hkx",
            "meshes\\actors\\dlc02\\netch\\behaviors\\netch.hkx",
            "meshes\\actors\\dlc02\\netch\\characterassets\\skeleton.hkx",
            "meshes\\actors\\character\\behaviors\\0_master.hkx",
            "meshes\\actors\\character\\character assets\\skeleton.hkx",
            "meshes\\actors\\character\\character assets female\\skeleton_female.hkx",
            "meshes\\actors\\ghost\\behaviors\\ghost.hkx"
        ])

        #expect(sets.map(\.name) == [
            "meshes\\actors\\canine", "meshes\\actors\\canine wolf", "meshes\\actors\\character",
            "meshes\\actors\\dlc02\\netch", "meshes\\actors\\ghost"
        ])
        #expect(sets.map(\.skeleton) == [
            "meshes\\actors\\canine\\character assets dog\\skeleton.hkx",
            "meshes\\actors\\canine\\character assets wolf\\skeleton.hkx",
            "meshes\\actors\\character\\character assets\\skeleton.hkx",
            "meshes\\actors\\dlc02\\netch\\characterassets\\skeleton.hkx",
            nil
        ])
        #expect(sets[0].behaviors == ["meshes\\actors\\canine\\behaviors\\dog.hkx"])
        #expect(sets[0].animations == ["meshes\\actors\\canine\\animations\\run.hkx"])
    }

    @Test func nodeClassesFollowHavokNaming() {
        #expect(BehaviorGapSweep.isNodeClass("hkbClipGenerator"))
        #expect(BehaviorGapSweep.isNodeClass("BSLookAtModifier"))
        #expect(BehaviorGapSweep.isNodeClass("hkbStateMachine"))
        #expect(!BehaviorGapSweep.isNodeClass("hkbStateMachineStateInfo"))
        #expect(!BehaviorGapSweep.isNodeClass("hkbBlenderGeneratorChild"))
    }
}
