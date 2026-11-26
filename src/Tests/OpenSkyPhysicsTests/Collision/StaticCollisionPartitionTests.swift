// A large triangle soup splits into leaves by where its triangles lie, so a query near
// one point meets few leaves. Synthetic meshes only.

@testable import OpenSkyFormatsCore
import OpenSkyFormatsMesh
@testable import OpenSkyPhysics
import simd
import Testing

struct StaticCollisionPartitionTests {
    /// A strip of `count` triangles along +X, written in an interleaved order, so a split
    /// by file order would give every leaf the whole strip.
    private static func strip(count: Int) -> (vertices: [SIMD3<Float>], indices: [UInt32]) {
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let order = (0 ..< count).map { ($0 * 37) % count }
        for step in order {
            let x = Float(step) * 10
            let base = UInt32(vertices.count)
            vertices += [SIMD3(x, 0, 0), SIMD3(x + 10, 0, 0), SIMD3(x, 10, 0)]
            indices += [base, base + 1, base + 2]
        }
        return (vertices, indices)
    }

    @Test func leavesCoverCompactAreasAndKeepEveryTriangle() {
        let (vertices, indices) = Self.strip(count: 256)
        let result = StaticCollisionShape.partitions(
            for: .triangleSoup(vertices: vertices, indices: indices)
        )
        #expect(result.failureCount == 0)
        #expect(result.partitions.count == 4)
        var kept = 0
        for partition in result.partitions {
            guard case let .triangleSoup(_, leaf) = partition.geometry else {
                Issue.record("a leaf is not a triangle soup")
                continue
            }
            kept += leaf.count / 3
            #expect(leaf.count / 3 <= 64)
            let width = partition.localBounds.max.x - partition.localBounds.min.x
            #expect(width <= 64 * 10 + 10, "a leaf spans \(width) of 2560 units")
        }
        #expect(kept == 256)
    }

    @Test func aSmallSoupStaysOneLeaf() {
        let (vertices, indices) = Self.strip(count: 10)
        let result = StaticCollisionShape.partitions(
            for: .triangleSoup(vertices: vertices, indices: indices)
        )
        #expect(result.partitions.count == 1)
    }
}
