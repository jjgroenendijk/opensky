// The decoded values of a behavior project, with an empty graph and a one-bone rig. A test
// of what is built from a decoded project uses them instead of a packfile per file.

import Foundation
@testable public import OpenSkyBehavior
@testable public import OpenSkyFormatsAnimation
import OpenSkyFormatsTesting
import simd

nonisolated public enum BehaviorProjectFixture {
    public static let folder = "meshes\\actors\\character"

    /// An object graph that holds no objects.
    public static func objectGraph() throws -> HKXObjectGraph {
        try HKXObjectGraph(file: HKXFile(data: HKXFixture().build()))
    }

    /// A graph with no root generator, so an instance of it poses nothing.
    public static let behavior = HKBBehaviorGraph(
        name: nil, userData: 0, variableMode: 0, rootGenerator: nil,
        rootGeneratorClassName: nil, data: nil, unresolved: []
    )

    public static let rig = HKASkeleton(
        name: nil,
        bones: [HKABone(name: "Root", lockTranslation: false)],
        parentIndices: [-1],
        referencePose: [HKABonePose(transform: matrix_identity_float4x4)]
    )

    /// The character project in `folder`, listing `clipPaths`.
    public static func asset(clipPaths: [String] = []) throws -> BehaviorProjectAsset {
        try BehaviorProjectAsset(
            projectPath: folder + "\\defaultmale.hkx",
            behaviorPath: folder + "\\behaviors\\0_master.hkx",
            objectGraph: objectGraph(),
            behavior: behavior,
            skeleton: rig,
            ragdollSkeleton: nil,
            rigPath: folder + "\\character assets\\skeleton.hkx",
            clipPaths: clipPaths
        )
    }
}
