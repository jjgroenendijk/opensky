// Unit tests for MatrixMath (AGENTS.md "Testing": every math routine tested).

@testable import opensky
import simd
import Testing

struct MatrixMathTests {
    @Test func radiansFromDegrees() {
        #expect(abs(MatrixMath.radians(fromDegrees: 180) - .pi) < 1e-6)
        #expect(MatrixMath.radians(fromDegrees: 0) == 0)
    }

    @Test func translationMovesPoint() {
        let matrix = MatrixMath.translation(SIMD3<Float>(1, 2, 3))
        let moved = matrix * SIMD4<Float>(0, 0, 0, 1)
        #expect(moved == SIMD4<Float>(1, 2, 3, 1))
    }

    @Test func rotationAboutZTurnsXAxisToY() {
        let matrix = MatrixMath.rotation(radians: .pi / 2, axis: SIMD3<Float>(0, 0, 1))
        let rotated = matrix * SIMD4<Float>(1, 0, 0, 0)
        #expect(abs(rotated.x) < 1e-6)
        #expect(abs(rotated.y - 1) < 1e-6)
        #expect(abs(rotated.z) < 1e-6)
    }

    @Test func rotationPreservesVectorLength() {
        let matrix = MatrixMath.rotation(radians: 1.234, axis: SIMD3<Float>(1, 1, 0))
        let original = SIMD4<Float>(3, -2, 5, 0)
        let rotated = matrix * original
        #expect(abs(simd_length(rotated) - simd_length(original)) < 1e-5)
    }

    @Test func rotationXYZMatchAxisAngleForm() {
        let angle: Float = 0.831
        let pairs: [(float4x4, SIMD3<Float>)] = [
            (MatrixMath.rotationX(radians: angle), SIMD3(1, 0, 0)),
            (MatrixMath.rotationY(radians: angle), SIMD3(0, 1, 0)),
            (MatrixMath.rotationZ(radians: angle), SIMD3(0, 0, 1))
        ]
        for (fixed, axis) in pairs {
            let general = MatrixMath.rotation(radians: angle, axis: axis)
            for column in 0 ..< 4 {
                #expect(simd_length(fixed[column] - general[column]) < 1e-6)
            }
        }
    }

    @Test func zUpToYUpMapsSkyrimAxesToMetalAxes() {
        let basis = MatrixMath.zUpToYUp
        // East stays right, up becomes view up, north recedes.
        #expect(basis * SIMD4<Float>(1, 0, 0, 0) == SIMD4<Float>(1, 0, 0, 0))
        #expect(basis * SIMD4<Float>(0, 0, 1, 0) == SIMD4<Float>(0, 1, 0, 0))
        #expect(basis * SIMD4<Float>(0, 1, 0, 0) == SIMD4<Float>(0, 0, -1, 0))
        // Proper rotation — no reflection sneaking in.
        #expect(abs(basis.determinant - 1) < 1e-6)
    }

    @Test func lookAtMapsEyeToOriginAndTargetDownNegativeZ() {
        let eye = SIMD3<Float>(10, -20, 5)
        let target = SIMD3<Float>(-3, 7, 40)
        let view = MatrixMath.lookAt(eye: eye, target: target, up: SIMD3(0, 0, 1))
        let eyeInView = view * SIMD4<Float>(eye.x, eye.y, eye.z, 1)
        #expect(simd_length(SIMD3(eyeInView.x, eyeInView.y, eyeInView.z)) < 1e-4)
        let targetInView = view * SIMD4<Float>(target.x, target.y, target.z, 1)
        #expect(abs(targetInView.x) < 1e-4)
        #expect(abs(targetInView.y) < 1e-4)
        #expect(targetInView.z < 0)
        #expect(abs(view.determinant - 1) < 1e-5)
    }

    @Test func lookAtConvertsZUpWorldToYUpEyeSpace() {
        // Camera at origin looking north (+Y) in Skyrim axes, world up = +Z.
        let view = MatrixMath.lookAt(
            eye: SIMD3(0, 0, 0),
            target: SIMD3(0, 1, 0),
            up: SIMD3(0, 0, 1)
        )
        // World up appears as eye-space up, east as right, north recedes.
        #expect(simd_length(view * SIMD4<Float>(0, 0, 1, 0) - SIMD4<Float>(0, 1, 0, 0)) < 1e-6)
        #expect(simd_length(view * SIMD4<Float>(1, 0, 0, 0) - SIMD4<Float>(1, 0, 0, 0)) < 1e-6)
        #expect(simd_length(view * SIMD4<Float>(0, 1, 0, 0) - SIMD4<Float>(0, 0, -1, 0)) < 1e-6)
    }

    @Test func placementWithZerosIsIdentity() {
        let matrix = MatrixMath.placement(
            position: SIMD3(0, 0, 0),
            rotation: SIMD3(0, 0, 0),
            scale: 1
        )
        for column in 0 ..< 4 {
            #expect(simd_length(matrix[column] - matrix_identity_float4x4[column]) < 1e-7)
        }
    }

    @Test func placementPutsModelOriginAtPosition() {
        let position = SIMD3<Float>(18650.6, -10797.2, -4584.3)
        let matrix = MatrixMath.placement(
            position: position,
            rotation: SIMD3(-0.19, 0.04, 3.9),
            scale: 1.39
        )
        let origin = matrix * SIMD4<Float>(0, 0, 0, 1)
        #expect(simd_length(SIMD3(origin.x, origin.y, origin.z) - position) < 1e-3)
    }

    @Test func placementYawIsClockwiseFromAbove() {
        // Bethesda +Z angle turns clockwise viewed from +Z: quarter turn sends
        // the model's +X (east) to -Y (south). See docs/decisions/coordinates.md.
        let matrix = MatrixMath.placement(
            position: SIMD3(0, 0, 0),
            rotation: SIMD3(0, 0, .pi / 2),
            scale: 1
        )
        let east = matrix * SIMD4<Float>(1, 0, 0, 0)
        #expect(simd_length(east - SIMD4<Float>(0, -1, 0, 0)) < 1e-6)
    }

    @Test func placementRoundTripsTranslationRotationScale() {
        let position = SIMD3<Float>(-321.5, 88, 1024)
        let rotation = SIMD3<Float>(0.21, -0.4, 2.9)
        let scale: Float = 0.87
        let matrix = MatrixMath.placement(position: position, rotation: rotation, scale: scale)

        // Translation column recovers position; basis columns recover uniform
        // scale and stay mutually orthogonal (pure rotation * scale).
        #expect(simd_length(SIMD3(
            matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z
        ) - position) < 1e-3)
        for column in 0 ..< 3 {
            let basis = SIMD3(matrix[column].x, matrix[column].y, matrix[column].z)
            #expect(abs(simd_length(basis) - scale) < 1e-5)
        }
        // Inverse maps the placed origin back to the model origin.
        let inverse = matrix.inverse
        let back = inverse * SIMD4<Float>(position.x, position.y, position.z, 1)
        #expect(simd_length(SIMD3(back.x, back.y, back.z)) < 1e-3)
    }

    @Test func perspectiveMapsNearToZeroAndFarToOne() {
        let matrix = MatrixMath.perspective(
            fovYRadians: .pi / 3,
            aspectRatio: 16.0 / 9.0,
            nearZ: 0.1,
            farZ: 100
        )
        let near = matrix * SIMD4<Float>(0, 0, -0.1, 1)
        let far = matrix * SIMD4<Float>(0, 0, -100, 1)
        #expect(abs(near.z / near.w) < 1e-5)
        #expect(abs(far.z / far.w - 1) < 1e-4)
    }
}
