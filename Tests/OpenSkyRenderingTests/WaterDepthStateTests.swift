import OpenSkyFormatsCore
@testable import OpenSkyRendering
import simd
import Testing

struct WaterDepthStateTests {
    @Test func unprojectTurnsStoredDepthBackIntoViewDepth() throws {
        let projection = MatrixMath.perspective(
            fovYRadians: 1.2, aspectRatio: 1.6, nearZ: 10, farZ: 400_000
        )
        let terms = try #require(WaterDepthState.unproject(projection))
        for viewDepth: Float in [12, 150, 3000, 90000] {
            let clip = projection * SIMD4(0, 0, -viewDepth, 1)
            let stored = clip.z / clip.w
            let recovered = terms.y / (stored + terms.x)
            #expect(abs(recovered - viewDepth) / viewDepth < 1e-3)
        }
    }

    @Test func anOrthographicProjectionHasNoUnproject() {
        let projection = MatrixMath.orthographic(OrthographicBounds(
            left: -1, right: 1, bottom: -1, top: 1, nearZ: 0, farZ: 10
        ))
        #expect(WaterDepthState.unproject(projection) == nil)
    }
}
