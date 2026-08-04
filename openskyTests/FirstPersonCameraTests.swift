// First-person camera parameters and the arms anchor (issue #190). Pure math —
// no install, no device.

@testable import opensky
import simd
import Testing

struct FirstPersonCameraTests {
    // MARK: - Field of view

    /// The default has to be the fov the scene pass actually projects with, or
    /// switching into first person would change the framing on its own.
    @Test
    func defaultFieldOfViewMatchesTheWorldProjection() {
        #expect(
            abs(FirstPersonCamera.defaultFOVYRadians - MatrixMath.radians(fromDegrees: 65))
                < 1e-6
        )
    }

    @Test
    func fieldOfViewClampsRatherThanRefusing() {
        var camera = FirstPersonCamera()
        camera.setFOVY(radians: MatrixMath.radians(fromDegrees: 5))
        #expect(camera.fovYRadians == FirstPersonCamera.fovYRange.lowerBound)
        camera.setFOVY(radians: MatrixMath.radians(fromDegrees: 400))
        #expect(camera.fovYRadians == FirstPersonCamera.fovYRange.upperBound)
        camera.setFOVY(radians: .nan)
        #expect(camera.fovYRadians == FirstPersonCamera.fovYRange.upperBound)
    }

    @Test
    func resetClearsTheOverride() {
        var camera = FirstPersonCamera()
        #expect(!camera.isOverridden)
        camera.setFOVY(radians: MatrixMath.radians(fromDegrees: 90))
        #expect(camera.isOverridden)
        camera.reset()
        #expect(!camera.isOverridden)
        #expect(camera.fovYRadians == FirstPersonCamera.defaultFOVYRadians)
    }

    @Test
    func degreesRoundTripThroughRadians() {
        let degrees: Float = 75
        let round = MatrixMath.degrees(
            fromRadians: MatrixMath.radians(fromDegrees: degrees)
        )
        #expect(abs(round - degrees) < 1e-4)
    }

    // MARK: - The eye

    /// Looking east and level, the rig's authored +Y forward has to end up on
    /// world +X and its +X on the camera's right, which in this basis is -Y.
    @Test
    func eyeMatrixTurnsTheRigOntoTheLookDirection() {
        let eye = SIMD3<Float>(10, -20, 130)
        let matrix = FirstPersonCamera.eyeMatrix(eyePosition: eye, yaw: 0, pitch: 0)
        #expect(simd_length(matrix.columns.3.xyz - eye) < 1e-4)
        let forward = matrix.columns.1.xyz
        #expect(simd_length(forward - SIMD3<Float>(1, 0, 0)) < 1e-4)
        let right = matrix.columns.0.xyz
        #expect(simd_length(right - SIMD3<Float>(0, -1, 0)) < 1e-4)
    }

    /// Pitching up tips the rig's forward axis up, which is what makes the arms
    /// follow the view rather than slide across it.
    @Test
    func pitchTipsTheRigForward() {
        let matrix = FirstPersonCamera.eyeMatrix(
            eyePosition: .zero, yaw: 0, pitch: MatrixMath.radians(fromDegrees: 30)
        )
        let forward = matrix.columns.1.xyz
        #expect(forward.z > 0.49 && forward.z < 0.51)
        #expect(abs(forward.x - cosf(MatrixMath.radians(fromDegrees: 30))) < 1e-4)
    }

    // MARK: - The rig anchor

    /// The whole point of the coupling: whatever the graph says about the
    /// camera bone, that bone lands on the eye matrix exactly.
    @Test
    func rigTransformPutsTheCameraBoneOnTheEye() {
        let eye = FirstPersonCamera.eyeMatrix(
            eyePosition: SIMD3<Float>(500, 100, 200),
            yaw: MatrixMath.radians(fromDegrees: 40),
            pitch: MatrixMath.radians(fromDegrees: -15)
        )
        let bone = MatrixMath.translation(SIMD3<Float>(0.5, -1, 121))
        let rig = FirstPersonCamera.rigTransform(eyeMatrix: eye, cameraBone: bone)
        let landed = rig * bone
        for index in 0 ..< 4 {
            #expect(simd_length(landed[index] - eye[index]) < 1e-3)
        }
    }

    /// A rotating camera bone rotates the view with it — the M15 case this
    /// composition exists to make free.
    @Test
    func rigTransformCarriesCameraBoneRotation() {
        let eye = FirstPersonCamera.eyeMatrix(eyePosition: .zero, yaw: 0, pitch: 0)
        let bone = MatrixMath.translation(SIMD3<Float>(0, 0, 121))
            * MatrixMath.rotationX(radians: MatrixMath.radians(fromDegrees: 20))
        let rig = FirstPersonCamera.rigTransform(eyeMatrix: eye, cameraBone: bone)
        let landed = rig * bone
        #expect(simd_length(landed.columns.1.xyz - eye.columns.1.xyz) < 1e-4)
        // The rig itself is tipped the other way, so the bone can be tipped
        // back onto the eye.
        #expect(rig.columns.1.z < -0.3)
    }

    /// No camera bone, or a degenerate one, falls back to the reference height
    /// rather than collapsing the arms onto the origin.
    @Test
    func missingCameraBoneFallsBackToTheReferenceHeight() {
        let eye = FirstPersonCamera.eyeMatrix(
            eyePosition: SIMD3<Float>(0, 0, 200), yaw: 0, pitch: 0
        )
        for bone in [nil, float4x4(0)] as [float4x4?] {
            let rig = FirstPersonCamera.rigTransform(eyeMatrix: eye, cameraBone: bone)
            let feet = rig.columns.3.xyz
            #expect(
                abs(feet.z - (200 - FirstPersonCamera.fallbackCameraBoneHeight)) < 1e-3
            )
        }
    }

    // MARK: - The depth policy

    /// The stated guarantee of the depth slice, recomputed from the projection
    /// rather than asserted as a number: every world fragment beyond this
    /// distance has a depth greater than the whole slice the arms occupy, so
    /// nothing reachable by world geometry can be drawn in front of them.
    @Test
    func depthSliceClearsEveryReachableWorldDistance() {
        let near = Renderer.nearPlane
        let far = Renderer.farPlane
        let projection = MatrixMath.perspective(
            fovYRadians: FirstPersonCamera.defaultFOVYRadians,
            aspectRatio: 1,
            nearZ: near,
            farZ: far
        )
        // The distance at which world depth first exceeds the slice.
        let breakEven = near / (1 - FirstPersonCamera.depthSlice)
        #expect(breakEven < PlayerCapsule.standard.radius)
        for distance in [breakEven + 0.5, 30, 100, 4096] as [Float] {
            let clip = projection * SIMD4<Float>(0, 0, -distance, 1)
            #expect(clip.z / clip.w > FirstPersonCamera.depthSlice, "at \(distance)")
        }
    }
}
