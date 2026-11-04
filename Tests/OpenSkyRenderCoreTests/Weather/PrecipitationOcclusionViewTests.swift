// The top-down rain occlusion view around the camera.

@testable import OpenSkyRenderCore
import simd
import Testing

struct PrecipitationOcclusionViewTests {
    let camera = SIMD3<Float>(1000, -2000, 500)

    func project(_ world: SIMD3<Float>) -> SIMD4<Float> {
        PrecipitationOcclusionView.matrix(camera: camera) * SIMD4(world, 1)
    }

    @Test
    func theCameraSitsInTheMiddle() {
        let view = project(camera)
        #expect(abs(view.x) < 0.01 && abs(view.y) < 0.01)
    }

    @Test
    func higherSurfacesAreNearer() {
        let roof = project(camera + SIMD3(0, 0, 300)).z
        let ground = project(camera - SIMD3(0, 0, 100)).z
        #expect(roof < ground)
        #expect(project(camera + SIMD3(0, 0, PrecipitationOcclusionView.reachAbove)).z.magnitude < 1e-4)
        #expect(abs(project(camera - SIMD3(0, 0, PrecipitationOcclusionView.reachBelow)).z - 1) < 1e-4)
    }

    @Test
    func theEdgeOfTheSquareIsTheEdgeOfClipSpace() {
        let edge = project(camera + SIMD3(PrecipitationOcclusionView.halfSize, 0, 0))
        #expect(abs(edge.x - 1) < 0.01)
    }
}
