// SceneCamera framing math (todo 2.7 app wiring): deterministic checks that
// the framing camera targets the bounds center, keeps the eye outside the
// box (south-west, above), and scales its distance with the bounds diagonal.

@testable import opensky
import simd
import Testing

struct SceneCameraTests {
    private let bounds = (
        min: SIMD3<Float>(-100, -200, 0),
        max: SIMD3<Float>(300, 400, 150)
    )

    @Test
    func demoMatchesDemoSceneConstants() {
        let camera = SceneCamera.demo
        #expect(camera.eye == DemoScene.cameraEye)
        #expect(camera.target == DemoScene.cameraTarget)
        #expect(camera.sunDirection == DemoScene.sunDirection)
        #expect(camera.sunColor == DemoScene.sunColor)
        #expect(camera.ambientColor == DemoScene.ambientColor)
    }

    @Test
    func framingTargetsBoundsCenter() {
        let camera = SceneCamera.framing(bounds: bounds)
        let center = (bounds.min + bounds.max) * 0.5
        #expect(camera.target == center)
    }

    @Test
    func framingEyeSitsSouthWestAboveOutsideBounds() {
        let camera = SceneCamera.framing(bounds: bounds)
        // South-west of and above the whole box — never inside it.
        #expect(camera.eye.x < bounds.min.x)
        #expect(camera.eye.y < bounds.min.y)
        #expect(camera.eye.z > bounds.max.z)
    }

    @Test
    func framingDistanceScalesWithDiagonal() {
        let doubled = (min: bounds.min * 2, max: bounds.max * 2)
        let single = SceneCamera.framing(bounds: bounds)
        let double = SceneCamera.framing(bounds: doubled)
        let singleDistance = simd_length(single.eye - single.target)
        let doubleDistance = simd_length(double.eye - double.target)
        #expect(abs(doubleDistance - 2 * singleDistance) < singleDistance * 1e-4)
    }

    @Test
    func framingDegenerateBoundsKeepMinimumDistance() {
        let point = SIMD3<Float>(10, 20, 30)
        let camera = SceneCamera.framing(bounds: (min: point, max: point))
        // Camera never collapses onto its target (near plane is 10 units).
        #expect(simd_length(camera.eye - camera.target) >= 64)
        #expect(camera.target == point)
    }

    @Test
    func framingReusesDemoLight() {
        let camera = SceneCamera.framing(bounds: bounds)
        #expect(camera.sunDirection == DemoScene.sunDirection)
        #expect(camera.sunColor == DemoScene.sunColor)
        #expect(camera.ambientColor == DemoScene.ambientColor)
    }
}
