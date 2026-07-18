// Demo scene sanity: generated geometry obeys the authoring conventions
// (CCW-from-outside winding consistent with stored normals, indices in
// range) and the built scene exercises both pipeline variants. Geometry
// checks are pure; the full build needs a Metal device (skipped on CI).

import Foundation
import Metal
@testable import opensky
import simd
import Testing

struct DemoSceneTests {
    private static let device = MTLCreateSystemDefaultDevice()

    private static var hasDevice: Bool {
        device != nil
    }

    private static var generatedMeshes: [Mesh] {
        [
            DemoScene.planeMesh(halfSize: 512, uvRepeat: 8),
            DemoScene.boxMesh(halfWidth: 32, halfDepth: 32, height: 64),
            DemoScene.panelMesh(halfWidth: 64, height: 128)
        ]
    }

    @Test func meshesAreWellFormed() {
        for mesh in Self.generatedMeshes {
            #expect(mesh.indices.count % 3 == 0)
            #expect(mesh.indices.allSatisfy { Int($0) < mesh.positions.count })
            #expect(mesh.normals.count == mesh.positions.count)
            #expect(mesh.uvs.count == mesh.positions.count)
        }
    }

    /// Winding convention (docs/decisions/coordinates.md): triangles wind
    /// counter-clockwise seen from outside, i.e. the right-hand-rule face
    /// normal of every triangle points the same way as its vertex normals.
    @Test func trianglesWindCounterClockwiseSeenFromOutside() {
        for mesh in Self.generatedMeshes {
            for triangle in stride(from: 0, to: mesh.indices.count, by: 3) {
                let first = Int(mesh.indices[triangle])
                let second = Int(mesh.indices[triangle + 1])
                let third = Int(mesh.indices[triangle + 2])
                let faceNormal = simd_cross(
                    mesh.positions[second] - mesh.positions[first],
                    mesh.positions[third] - mesh.positions[first]
                )
                let vertexNormal = mesh.normals[first]
                #expect(
                    simd_dot(faceNormal, vertexNormal) > 0,
                    "triangle \(triangle / 3) of \(mesh.name ?? "?") winds against its normal"
                )
            }
        }
    }

    @Test(.enabled(if: Self.hasDevice)) func buildsSceneWithBothPipelineVariants() throws {
        let device = try #require(Self.device)
        let scene = try DemoScene.build(device: device)

        // Opaque groups: ground + crate (three crates collapse to one
        // instanced group); cutout panel = alpha-tested and double-sided.
        #expect(scene.opaque.count == 2)
        #expect(scene.opaque.map(\.instances.count).sorted() == [1, 3])
        #expect(scene.alphaTested.count == 1)
        #expect(scene.instanceCount == 5)
        for group in scene.alphaTested {
            #expect(group.material.doubleSided)
        }
        // Every demo instance carries real world bounds (culling path).
        for group in scene.opaque + scene.alphaTested {
            #expect(group.instances.allSatisfy { $0.bounds != nil })
        }
        #expect(!scene.residencyAllocations.isEmpty)
    }
}
