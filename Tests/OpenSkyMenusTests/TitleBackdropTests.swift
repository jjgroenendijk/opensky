// The logo backdrop sits on the view line, in front of the camera, facing it,
// and the smoke stands behind it with the camera outside.

import OpenSkyMenus
import simd
import Testing

struct TitleBackdropTests {
    private let view = TitleBackdrop.View(
        eye: SIMD3(100, 200, 300), forward: SIMD3(1, 0, 0), right: SIMD3(0, -1, 0)
    )
    private let logo = TitleBackdrop.Box(min: SIMD3(-10, -2, 0), max: SIMD3(10, 2, 8))

    private func point(_ matrix: float4x4, _ local: SIMD3<Float>) -> SIMD3<Float> {
        let world = matrix * SIMD4(local, 1)
        return SIMD3(world.x, world.y, world.z)
    }

    @Test func theLogoCenterLandsOnTheViewLineFacingTheCamera() {
        let matrix = TitleBackdrop.logoTransform(view: view, logo: logo)
        let radius = simd_length(SIMD3<Float>(20, 4, 8)) / 2
        let expected = view.eye + view.forward * radius * TitleBackdrop.distanceInRadii
        #expect(simd_distance(point(matrix, SIMD3(0, 0, 4)), expected) < 0.001)
        let front = matrix * SIMD4<Float>(0, 1, 0, 0)
        #expect(SIMD3(front.x, front.y, front.z) == -view.forward)
        #expect(matrix.columns.2 == SIMD4<Float>(0, 0, 1, 0))
    }

    @Test func theSmokeStandsBehindTheLogoWithTheCameraOutside() {
        let fog = TitleBackdrop.Box(min: SIMD3(-400, -300, -400), max: SIMD3(400, 300, 200))
        let logoMatrix = TitleBackdrop.logoTransform(view: view, logo: logo)
        let fogMatrix = TitleBackdrop.fogTransform(view: view, logo: logo, fog: fog)
        let logoCenter = point(logoMatrix, SIMD3(0, 0, 4))
        // The fog's near face (+Y side) lands at the logo, on the view line.
        let nearFace = point(fogMatrix, SIMD3(0, 300, -100))
        #expect(simd_distance(nearFace, logoCenter) < 0.001)
        let farFace = point(fogMatrix, SIMD3(0, -300, -100))
        #expect(simd_dot(farFace - view.eye, view.forward) > simd_dot(
            logoCenter - view.eye, view.forward
        ))
    }
}
