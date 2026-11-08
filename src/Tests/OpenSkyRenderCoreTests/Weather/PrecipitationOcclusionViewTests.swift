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
        #expect(project(camera + SIMD3(0, 0, PrecipitationOcclusionView.reachAbove)).z
            .magnitude < 1e-4)
        #expect(abs(project(camera - SIMD3(0, 0, PrecipitationOcclusionView.reachBelow)).z - 1) <
            1e-4)
    }

    @Test
    func theEdgeOfTheSquareIsTheEdgeOfClipSpace() {
        let edge = project(camera + SIMD3(PrecipitationOcclusionView.halfSize, 0, 0))
        #expect(abs(edge.x - 1) < 0.01)
    }

    @Test
    func aSlantedFallMapsAPathToOneTexel() {
        let fall = simd_normalize(SIMD3<Float>(300, -100, -1900))
        let matrix = PrecipitationOcclusionView.matrix(camera: camera, fall: fall)
        let ground = camera + SIMD3(200, 50, -100)
        let above = ground - fall * 3000
        let low = matrix * SIMD4(ground, 1)
        let high = matrix * SIMD4(above, 1)
        #expect(simd_distance(SIMD2(low.x, low.y), SIMD2(high.x, high.y)) < 1e-4)
        #expect(high.z < low.z)
    }

    @Test
    func aNearlyFlatFallKeepsTheSteepestSlant() {
        let slant = PrecipitationOcclusionView.slant(of: SIMD3(10, 0, -1))
        #expect(abs(simd_length(slant) - PrecipitationOcclusionView.maximumSlant) < 1e-5)
        #expect(PrecipitationOcclusionView.slant(of: SIMD3(1, 0, 0)) == .zero)
    }
}
