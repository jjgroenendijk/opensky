// The movie quad: it covers the whole frame, and its uv leaves 0 to 1 where the
// letterbox bars are, so the shader draws them black.

@testable import OpenSkyRendering
import OpenSkyShaderTypes
import simd
import Testing

struct MovieLayerTests {
    @Test
    func aWidePictureOnATallerFrameGetsBarsAboveAndBelow() {
        let vertices = MovieLayer.vertices(
            picture: SIMD2(1920, 1080), target: SIMD2(1600, 1200), fullRange: false
        )
        #expect(vertices.count == MovieLayer.verticesPerQuad)
        let us = vertices.map(\.uv.x)
        let vs = vertices.map(\.uv.y)
        #expect(us.min() == 0 && us.max() == 1)
        // The picture fills 900 of 1200 rows, so the uv runs 1200 / 900 of its height.
        #expect(abs((vs.max() ?? 0) - (vs.min() ?? 0) - 4.0 / 3.0) < 1e-5)
        #expect(abs((vs.min() ?? 0) + 1.0 / 6.0) < 1e-5)
        #expect(vertices.allSatisfy { $0.color.x == 0 })
    }

    @Test
    func noLetterboxStretchesThePicture() {
        let vertices = MovieLayer.vertices(
            picture: SIMD2(1920, 1080), target: SIMD2(1600, 1200), fullRange: true,
            letterbox: false
        )
        #expect(vertices.allSatisfy { (0 ... 1).contains($0.uv.x) && (0 ... 1).contains($0.uv.y) })
        #expect(vertices.allSatisfy { $0.color.x == 1 })
        #expect(Set(vertices.map { [$0.position.x, $0.position.y] }).count == 4)
    }
}
