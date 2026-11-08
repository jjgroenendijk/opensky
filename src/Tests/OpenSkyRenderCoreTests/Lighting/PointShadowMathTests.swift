// The point light cube faces: the matrix each face draws with must give the same
// position and depth as the shader's face rule.

import Foundation
@testable import OpenSkyRenderCore
import simd
import Testing

struct PointShadowMathTests {
    struct Lookup {
        let face: Int
        let uv: SIMD2<Float>
        let depth: Float
    }

    /// The scene shader's lookup, written out in Swift.
    static func shaderLookup(_ offset: SIMD3<Float>, radius: Float) -> Lookup {
        let face = PointShadowMath.face(of: offset)
        let (forward, up) = PointShadowMath.faces[face]
        let right = simd_cross(forward, up)
        let along = simd_dot(offset, forward)
        let ndc = SIMD2(simd_dot(offset, right), simd_dot(offset, up)) / along
        let near = PointShadowMath.nearPlane
        let far = PointShadowMath.farPlane(radius: radius)
        return Lookup(
            face: face, uv: ndc * SIMD2(0.5, -0.5) + 0.5,
            depth: far / (far - near) * (1 - near / along)
        )
    }

    @Test func everyFaceMatrixMatchesTheShaderLookup() {
        let light = SIMD3<Float>(100, -40, 250)
        let offsets: [SIMD3<Float>] = [
            SIMD3(300, 50, -20), SIMD3(-200, 30, 90), SIMD3(10, 400, -100),
            SIMD3(-60, -350, 20), SIMD3(40, -70, 500), SIMD3(-30, 80, -260)
        ]
        for (expectedFace, offset) in offsets.enumerated() {
            let lookup = Self.shaderLookup(offset, radius: 1024)
            #expect(lookup.face == expectedFace)
            let clip = PointShadowMath.viewProjection(light: light, face: lookup.face, radius: 1024)
                * SIMD4(light + offset, 1)
            let ndc = SIMD3(clip.x, clip.y, clip.z) / clip.w
            let uv = SIMD2(ndc.x, ndc.y) * SIMD2(0.5, -0.5) + 0.5
            #expect(simd_distance(uv, lookup.uv) < 1e-4)
            #expect(abs(ndc.z - lookup.depth) < 1e-4)
            #expect(ndc.z > 0 && ndc.z < 1)
        }
    }

    @Test func theFacesKeepTheWindingOfARotation() {
        for face in 0 ..< PointShadowMath.faceCount {
            let (forward, up) = PointShadowMath.faces[face]
            #expect(simd_cross(simd_cross(forward, up), up) == -forward)
        }
    }

    @Test func theNearestLightsBySphereWin() {
        let viewer = SIMD3<Float>(0, 0, 0)
        let picked = PointShadowMath.pick(
            [
                PointShadowCandidate(index: 0, position: SIMD3(2000, 0, 0), radius: 100),
                PointShadowCandidate(index: 1, position: SIMD3(600, 0, 0), radius: 700),
                PointShadowCandidate(index: 2, position: SIMD3(300, 0, 0), radius: 100),
                PointShadowCandidate(index: 3, position: SIMD3(9000, 0, 0), radius: 100)
            ],
            viewer: viewer, limit: 2
        )
        #expect(picked == [1, 2])
        #expect(PointShadowMath.pick(
            [PointShadowCandidate(index: 3, position: SIMD3(9000, 0, 0), radius: 100)],
            viewer: viewer
        ).isEmpty)
    }
}
