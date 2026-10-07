// Meshlet splitting on synthetic grids: every triangle lands in exactly one meshlet, no
// meshlet passes the limits, and the bounds and normal cones hold what they claim.

@testable import OpenSkyRendering
import simd
import Testing

struct MeshletBuilderTests {
    /// A flat grid of `cells` x `cells` quads in the XY plane, facing +Z.
    private static func grid(cells: Int) -> (indices: [UInt16], positions: [SIMD3<Float>]) {
        var positions: [SIMD3<Float>] = []
        for y in 0 ... cells {
            for x in 0 ... cells {
                positions.append(SIMD3(Float(x), Float(y), 0))
            }
        }
        var indices: [UInt16] = []
        let row = cells + 1
        for y in 0 ..< cells {
            for x in 0 ..< cells {
                let corner = UInt16(y * row + x)
                let up = corner + UInt16(row)
                indices += [corner, corner + 1, up + 1, corner, up + 1, up]
            }
        }
        return (indices, positions)
    }

    /// Each triangle as its three mesh vertex indices, rebuilt from the meshlets.
    private static func triangles(_ mesh: MeshletMesh) -> [[UInt32]] {
        mesh.meshlets.flatMap { meshlet in
            (0 ..< Int(meshlet.triangleCount)).map { triangle in
                (0 ..< 3).map { corner in
                    let local = mesh.triangleIndices[
                        (Int(meshlet.triangleOffset) + triangle) * 3 + corner
                    ]
                    return mesh.vertexIndices[Int(meshlet.vertexOffset) + Int(local)]
                }
            }
        }
    }

    @Test
    func aSmallMeshIsOneMeshletWithTheSameTriangles() {
        let (indices, positions) = Self.grid(cells: 2)
        let mesh = MeshletBuilder.build(indices: indices, positions: positions)
        #expect(mesh.meshlets.count == 1)
        #expect(mesh.meshlets[0].vertexCount == 9)
        #expect(mesh.meshlets[0].triangleCount == 8)
        let expected = stride(from: 0, to: indices.count, by: 3).map { start in
            indices[start ..< start + 3].map(UInt32.init)
        }
        #expect(Self.triangles(mesh) == expected)
    }

    @Test
    func aLargeMeshSplitsWithinTheLimits() {
        let (indices, positions) = Self.grid(cells: 20)
        let mesh = MeshletBuilder.build(indices: indices, positions: positions)
        #expect(mesh.meshlets.count > 1)
        for meshlet in mesh.meshlets {
            #expect(meshlet.vertexCount <= UInt32(MeshletBuilder.maximumVertices))
            #expect(meshlet.triangleCount <= UInt32(MeshletBuilder.maximumTriangles))
        }
        #expect(mesh.triangleCount == indices.count / 3)
        #expect(Self.triangles(mesh).count == indices.count / 3)
    }

    @Test
    func theSphereHoldsEveryVertexOfItsMeshlet() {
        let (indices, positions) = Self.grid(cells: 20)
        let mesh = MeshletBuilder.build(indices: indices, positions: positions)
        for meshlet in mesh.meshlets {
            let start = Int(meshlet.vertexOffset)
            for index in mesh.vertexIndices[start ..< start + Int(meshlet.vertexCount)] {
                let distance = simd_distance(positions[Int(index)], meshlet.center)
                #expect(distance <= meshlet.radius + 1e-4)
            }
        }
    }

    @Test
    func aFlatMeshletHasANarrowConeAndAFoldedOneHasNone() {
        let (indices, positions) = Self.grid(cells: 2)
        let flat = MeshletBuilder.build(indices: indices, positions: positions).meshlets[0]
        #expect(simd_distance(flat.coneAxis, SIMD3(0, 0, 1)) < 1e-5)
        #expect(abs(flat.coneCutoff) < 1e-5)
        // The same quad twice, once each way round: a two-sided blade.
        let folded = MeshletBuilder.build(
            indices: [0, 1, 2, 0, 2, 1],
            positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)]
        ).meshlets[0]
        #expect(folded.coneCutoff == -1)
    }

    @Test
    func trianglesNamingMissingVerticesAreDropped() {
        let mesh = MeshletBuilder.build(
            indices: [0, 1, 2, 0, 2, 9, 7],
            positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)]
        )
        #expect(mesh.triangleCount == 1)
        #expect(MeshletBuilder.build(indices: [], positions: []).meshlets.isEmpty)
    }
}
