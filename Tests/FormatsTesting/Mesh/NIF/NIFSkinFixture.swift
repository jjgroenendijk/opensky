// Skinned block chains that the skin suites share, built from `NIFFixture`.

import Foundation
import simd

extension NIFFixture {
    /// Root (block 0), one bone (1), a `BSDynamicTriShape` (2) at `positions`
    /// over `inherited`, and its one-bone skin instance (3), data (4), and
    /// `partition` (5).
    public static func dynamicSkinBlocks(
        root: Data = niNode(children: [1, 2]),
        bone: Data = niNode(),
        inherited: Data,
        positions: [SIMD3<Float>],
        partition: Data
    ) -> [Block] {
        [
            .init("NiNode", root),
            .init("NiNode", bone),
            .init(
                "BSDynamicTriShape",
                bsDynamicTriShape(inherited: inherited, positions: positions)
            ),
            .init("NiSkinInstance", skinInstance(
                dataRef: 4, partitionRef: 5, skeletonRootRef: 0, boneRefs: [1]
            )),
            .init("NiSkinData", skinData(boneTransforms: [niTransform()], vertexWeights: [[]])),
            .init("NiSkinPartition", partition)
        ]
    }
}
