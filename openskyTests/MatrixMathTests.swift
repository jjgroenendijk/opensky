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
