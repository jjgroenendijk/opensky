// `PlayImpactEffect`'s "local rotation" is a node's turn inside its parent node.

@testable import OpenSkyFormatsCore
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct PosedBoneTests {
    private static func turn(_ degrees: Float) -> float4x4 {
        float4x4(simd_quatf(angle: degrees * .pi / 180, axis: SIMD3(0, 0, 1)))
    }

    private static func isClose(_ lhs: float4x4, _ rhs: float4x4) -> Bool {
        (0 ..< 4).allSatisfy { simd_distance(lhs[$0], rhs[$0]) < 1e-5 }
    }

    @Test
    func aChildIsReadInsideItsParent() throws {
        let parent = Self.turn(30)
        let child = parent * Self.turn(45)
        let bone = try #require(PosedBone(index: 1, matrices: [parent, child], parents: [-1, 0]))
        #expect(Self.isClose(bone.model, child))
        #expect(Self.isClose(bone.local, Self.turn(45)))
    }

    @Test
    func aRootOrAnUnposedBoneIsItsOwnLocal() throws {
        let root = try #require(PosedBone(index: 0, matrices: [Self.turn(30)], parents: [-1]))
        #expect(Self.isClose(root.local, Self.turn(30)))
        let orphan = try #require(PosedBone(index: 0, matrices: [Self.turn(10)], parents: [5]))
        #expect(Self.isClose(orphan.local, Self.turn(10)))
        #expect(PosedBone(index: 2, matrices: [Self.turn(10)], parents: []) == nil)
    }
}
