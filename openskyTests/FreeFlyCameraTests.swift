// Free-fly camera math (todo 2.8): orientation vs coordinate conventions,
// pitch clamp, movement direction relative to yaw, speed + boost. Pure math,
// synthetic inputs (AGENTS.md testing rule).

@testable import opensky
import simd
import Testing

struct FreeFlyCameraTests {
    private let origin = SIMD3<Float>(0, 0, 0)

    @Test
    func forwardAtYawZeroPitchZeroPointsEast() {
        let camera = FreeFlyCamera(position: origin, yaw: 0, pitch: 0)
        // Yaw 0 -> +X (east), pitch 0 -> level. docs/decisions/coordinates.md.
        #expect(abs(camera.forward.x - 1) < 1e-6)
        #expect(abs(camera.forward.y) < 1e-6)
        #expect(abs(camera.forward.z) < 1e-6)
    }

    @Test
    func forwardAtYawNinetyPointsNorth() {
        let camera = FreeFlyCamera(position: origin, yaw: .pi / 2, pitch: 0)
        #expect(abs(camera.forward.x) < 1e-6)
        #expect(abs(camera.forward.y - 1) < 1e-6)
        #expect(abs(camera.forward.z) < 1e-6)
    }

    @Test
    func positivePitchLooksUp() {
        let camera = FreeFlyCamera(position: origin, yaw: 0, pitch: .pi / 4)
        #expect(camera.forward.z > 0)
    }

    @Test
    func rightIsHorizontalAndPerpendicularToLevelForward() {
        let camera = FreeFlyCamera(position: origin, yaw: 0.7, pitch: 0.9)
        // Strafing stays level regardless of pitch.
        #expect(abs(camera.right.z) < 1e-6)
        #expect(abs(simd_length(camera.right) - 1) < 1e-6)
        // Yaw 0 -> right points south (-Y), matching cross(forward, +Z).
        let level = FreeFlyCamera(position: origin, yaw: 0, pitch: 0)
        #expect(abs(level.right.x) < 1e-6)
        #expect(abs(level.right.y + 1) < 1e-6)
    }

    @Test
    func pitchClampsAtLimit() {
        var camera = FreeFlyCamera(position: origin, yaw: 0, pitch: 0)
        camera.applyLook(lookRight: 0, lookUp: 100_000)
        #expect(camera.pitch <= FreeFlyCamera.maxPitch + 1e-6)
        camera.applyLook(lookRight: 0, lookUp: -1_000_000)
        #expect(camera.pitch >= -FreeFlyCamera.maxPitch - 1e-6)
    }

    @Test
    func initClampsOutOfRangePitch() {
        let camera = FreeFlyCamera(position: origin, yaw: 0, pitch: .pi)
        #expect(camera.pitch <= FreeFlyCamera.maxPitch + 1e-6)
    }

    @Test
    func pointerRightTurnsViewRight() {
        var camera = FreeFlyCamera(position: origin, yaw: 0, pitch: 0)
        camera.applyLook(lookRight: 100, lookUp: 0)
        // Turning right from east -> toward south (-Y): forward.y goes negative.
        #expect(camera.forward.y < 0)
    }

    @Test
    func forwardMoveFollowsHeading() {
        var camera = FreeFlyCamera(position: origin, yaw: 0, pitch: 0)
        let dt: Float = 0.5
        camera.applyMove(forwardAxis: 1, rightAxis: 0, upAxis: 0, boost: false, dt: dt)
        // Moves along +X by baseSpeed * dt.
        #expect(abs(camera.position.x - FreeFlyCamera.baseSpeed * dt) < 1e-2)
        #expect(abs(camera.position.y) < 1e-3)
        #expect(abs(camera.position.z) < 1e-3)
    }

    @Test
    func strafeFollowsRightVector() {
        var camera = FreeFlyCamera(position: origin, yaw: 0, pitch: 0)
        camera.applyMove(forwardAxis: 0, rightAxis: 1, upAxis: 0, boost: false, dt: 1)
        // Right at yaw 0 = south (-Y).
        #expect(camera.position.y < 0)
        #expect(abs(camera.position.x) < 1e-3)
        #expect(abs(camera.position.z) < 1e-3)
    }

    @Test
    func verticalMoveFollowsWorldUp() {
        var camera = FreeFlyCamera(position: origin, yaw: 1.3, pitch: 0.6)
        camera.applyMove(forwardAxis: 0, rightAxis: 0, upAxis: 1, boost: false, dt: 1)
        // World +Z only, independent of heading.
        #expect(abs(camera.position.x) < 1e-3)
        #expect(abs(camera.position.y) < 1e-3)
        #expect(camera.position.z > 0)
    }

    @Test
    func boostMultipliesSpeed() {
        var plain = FreeFlyCamera(position: origin, yaw: 0, pitch: 0)
        var boosted = FreeFlyCamera(position: origin, yaw: 0, pitch: 0)
        plain.applyMove(forwardAxis: 1, rightAxis: 0, upAxis: 0, boost: false, dt: 1)
        boosted.applyMove(forwardAxis: 1, rightAxis: 0, upAxis: 0, boost: true, dt: 1)
        let ratio = boosted.position.x / plain.position.x
        #expect(abs(ratio - FreeFlyCamera.boostMultiplier) < 1e-4)
    }

    @Test
    func diagonalMoveNotFaster() {
        var camera = FreeFlyCamera(position: origin, yaw: 0, pitch: 0)
        camera.applyMove(forwardAxis: 1, rightAxis: 1, upAxis: 0, boost: false, dt: 1)
        // Normalized direction -> total distance is baseSpeed, not sqrt(2) more.
        #expect(abs(simd_length(camera.position) - FreeFlyCamera.baseSpeed) < 1e-1)
    }

    @Test
    func zeroInputDoesNotMove() {
        var camera = FreeFlyCamera(position: origin, yaw: 0.5, pitch: 0.2)
        camera.applyMove(forwardAxis: 0, rightAxis: 0, upAxis: 0, boost: false, dt: 1)
        #expect(camera.position == origin)
    }

    @Test
    func crossingOneCellTakesSeconds() {
        // Cell = 4096 units; base speed should cross it in a few seconds.
        let seconds = 4096 / FreeFlyCamera.baseSpeed
        #expect(seconds > 1)
        #expect(seconds < 5)
    }

    @Test
    func seededFromFramingCameraReproducesView() {
        let scene = SceneCamera(
            eye: SIMD3<Float>(-380, -480, 280),
            target: SIMD3<Float>(0, 0, 48),
            sunDirection: DemoScene.sunDirection,
            sunColor: DemoScene.sunColor,
            ambientColor: DemoScene.ambientColor
        )
        let camera = FreeFlyCamera(framing: scene)
        #expect(camera.position == scene.eye)
        // Reconstructed forward matches eye -> target direction.
        let expected = simd_normalize(scene.target - scene.eye)
        let forward = camera.forward
        #expect(abs(forward.x - expected.x) < 1e-5)
        #expect(abs(forward.y - expected.y) < 1e-5)
        #expect(abs(forward.z - expected.z) < 1e-5)
    }

    @Test
    func viewMatrixPlacesFrontGeometryDownNegativeZ() {
        let camera = FreeFlyCamera(position: origin, yaw: 0, pitch: 0)
        let view = camera.viewMatrix()
        // A world point due east (in front) lands at negative eye-space z.
        let ahead = view * SIMD4<Float>(100, 0, 0, 1)
        #expect(ahead.z < 0)
        // Eye at origin maps to eye-space origin.
        let eye = view * SIMD4<Float>(0, 0, 0, 1)
        #expect(abs(eye.x) < 1e-5)
        #expect(abs(eye.y) < 1e-5)
        #expect(abs(eye.z) < 1e-5)
    }
}
