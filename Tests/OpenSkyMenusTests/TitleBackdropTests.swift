// The logo backdrop sits on the view line, in front of the camera, facing it.

import OpenSkyMenus
import simd
import Testing

struct TitleBackdropTests {
    @Test func theLogoCenterLandsOnTheViewLineFacingTheCamera() {
        let eye = SIMD3<Float>(100, 200, 300)
        let forward = SIMD3<Float>(1, 0, 0)
        let right = SIMD3<Float>(0, -1, 0)
        let matrix = TitleBackdrop.transform(
            eye: eye, forward: forward, right: right,
            boundsMin: SIMD3(-10, -2, 0), boundsMax: SIMD3(10, 2, 8)
        )
        let center = matrix * SIMD4<Float>(0, 0, 4, 1)
        let radius = simd_length(SIMD3<Float>(20, 4, 8)) / 2
        let expected = eye + forward * radius * TitleBackdrop.distanceInRadii
        #expect(simd_distance(SIMD3(center.x, center.y, center.z), expected) < 0.001)
        let front = matrix * SIMD4<Float>(0, 1, 0, 0)
        #expect(SIMD3(front.x, front.y, front.z) == -forward)
        #expect(matrix.columns.2 == SIMD4<Float>(0, 0, 1, 0))
    }
}
