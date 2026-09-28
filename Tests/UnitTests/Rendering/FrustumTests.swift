// Unit tests for Frustum (AGENTS.md "Testing": every math routine tested).
// View-projection built from the same MatrixMath calls + Renderer near/far
// constants the renderer uses (see Renderer.swift projection setup), camera
// looking north (+Y world) with world up = +Z, matching MatrixMathTests style.

@testable import opensky
import simd
import Testing

struct FrustumTests {
    /// Camera at the world origin, looking north (+Y), world up +Z — so in
    /// eye space east (+X world) is right and up (+Z world) is up. Matches
    /// Renderer's actual perspective params (65 deg vertical fov, near/far
    /// from Renderer.nearPlane/farPlane).
    static func makeFrustum(aspectRatio: Float = 16.0 / 9.0) -> Frustum {
        let view = MatrixMath.lookAt(
            eye: SIMD3<Float>(0, 0, 0),
            target: SIMD3<Float>(0, 1, 0),
            up: SIMD3<Float>(0, 0, 1)
        )
        let projection = MatrixMath.perspective(
            fovYRadians: MatrixMath.radians(fromDegrees: 65),
            aspectRatio: aspectRatio,
            nearZ: Renderer.nearPlane,
            farZ: Renderer.farPlane
        )
        return Frustum(viewProjection: projection * view)
    }

    @Test func boxStraightAheadIsInside() {
        let frustum = Self.makeFrustum()
        #expect(frustum.intersects(
            min: SIMD3<Float>(-10, 900, -10),
            max: SIMD3<Float>(10, 1100, 10)
        ))
    }

    @Test func boxBehindCameraIsOutside() {
        let frustum = Self.makeFrustum()
        #expect(!frustum.intersects(
            min: SIMD3<Float>(-10, -1100, -10),
            max: SIMD3<Float>(10, -900, 10)
        ))
    }

    @Test func boxFarLeftIsOutside() {
        // East (+X) is the camera's right, so far-left is -X.
        let frustum = Self.makeFrustum()
        #expect(!frustum.intersects(
            min: SIMD3<Float>(-5100, 900, -10),
            max: SIMD3<Float>(-4900, 1100, 10)
        ))
    }

    @Test func boxFarRightIsOutside() {
        let frustum = Self.makeFrustum()
        #expect(!frustum.intersects(
            min: SIMD3<Float>(4900, 900, -10),
            max: SIMD3<Float>(5100, 1100, 10)
        ))
    }

    @Test func boxFarAboveIsOutside() {
        let frustum = Self.makeFrustum()
        #expect(!frustum.intersects(
            min: SIMD3<Float>(-10, 900, 4900),
            max: SIMD3<Float>(10, 1100, 5100)
        ))
    }

    @Test func boxFarBelowIsOutside() {
        let frustum = Self.makeFrustum()
        #expect(!frustum.intersects(
            min: SIMD3<Float>(-10, 900, -5100),
            max: SIMD3<Float>(10, 1100, -4900)
        ))
    }

    @Test func boxStraddlingNearPlaneIsInside() {
        // Near = 10 units; box spans world-north distance 5...15, straddling
        // it. Conservative test keeps straddling boxes.
        let frustum = Self.makeFrustum()
        #expect(frustum.intersects(
            min: SIMD3<Float>(-1, 5, -1),
            max: SIMD3<Float>(1, 15, 1)
        ))
    }

    @Test func boxBeyondFarPlaneIsOutside() {
        // Far = 65536 units; box entirely past it, no straddle.
        let frustum = Self.makeFrustum()
        #expect(!frustum.intersects(
            min: SIMD3<Float>(-10, 100_000, -10),
            max: SIMD3<Float>(10, 100_010, 10)
        ))
    }

    @Test func hugeBoxEnclosingFrustumIsInside() {
        let frustum = Self.makeFrustum()
        #expect(frustum.intersects(
            min: SIMD3<Float>(-1_000_000, -1_000_000, -1_000_000),
            max: SIMD3<Float>(1_000_000, 1_000_000, 1_000_000)
        ))
    }

    @Test func degenerateZeroSizeBoxInsideIsInside() {
        let frustum = Self.makeFrustum()
        let point = SIMD3<Float>(0, 1000, 0)
        #expect(frustum.intersects(min: point, max: point))
    }

    @Test func modelBoundsOverloadMatchesMinMax() {
        let frustum = Self.makeFrustum()
        let bounds = ModelBounds(
            min: SIMD3<Float>(-10, 900, -10),
            max: SIMD3<Float>(10, 1100, 10)
        )
        #expect(frustum.intersects(bounds) == frustum.intersects(min: bounds.min, max: bounds.max))
    }
}
