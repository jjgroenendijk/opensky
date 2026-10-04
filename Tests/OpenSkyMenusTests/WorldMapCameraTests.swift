// The world map camera stays inside the worldspace's map limits.

@testable import OpenSkyMenus
import Testing

struct WorldMapCameraTests {
    private static let limits = WorldMapLimits(
        minimum: SIMD2(-1000, -1000), maximum: SIMD2(1000, 1000),
        minHeight: 100, maxHeight: 400, initialPitch: 50
    )

    @Test func panZoomAndTiltAreClampedToTheLimits() {
        var camera = WorldMapCamera(limits: Self.limits, focus: SIMD2(5000, 0))
        #expect(camera.focus == SIMD2(1000, 0), "the start focus is clamped")
        #expect(camera.height == 400)
        camera.zoom(by: 1000)
        #expect(camera.height == 100)
        camera.pan(by: SIMD2(-400, 0))
        #expect(camera.focus.x == 900, "a pan is scaled by height over the top height")
        camera.tilt(by: 100)
        #expect(camera.pitch == WorldMapCamera.maxPitch)
        #expect(camera.eye == SIMD3(900, 0, 100), "straight down at 90 degrees")
    }
}
