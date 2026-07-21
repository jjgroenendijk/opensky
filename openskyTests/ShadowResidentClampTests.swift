// Resident-bounds near-plane clamp for cascaded sun shadows (M7.1.2). The
// scene is the resident cell set, so its world-AABB union bounds every caster:
// clamping each cascade's casterBackup extension to it is a precision/cost win,
// never a visual change. Pure math, synthetic fixtures (AGENTS.md testing).
//
// Light-space near-distance convention: MatrixMath.orthographic takes a
// positive near distance; the slice's nearest corner is at sliceNearZ and the
// full 7.1.1 backup pushes it toward the sun to fullBackupNearZ (more
// negative). residentNearZ is resident geometry's nearest-toward-sun distance.

@testable import opensky
import simd
import Testing

struct ShadowResidentClampTests {
    // MARK: - clampedShadowNearZ scalar behavior

    @Test func clampReducesRangeWhenResidentInsideBackup() {
        // Resident geometry sits between the slice near and the full backup:
        // the near plane pulls back to it, shrinking the light Z range.
        let near = ShadowCascadeMath.clampedShadowNearZ(
            sliceNearZ: -10,
            fullBackupNearZ: -1000,
            residentNearZ: -200
        )
        #expect(near == -200)
        #expect(near > -1000, "clamp must shrink the backup extension")
    }

    @Test func clampNeverCutsCastersInsideBounds() {
        // Whenever resident geometry is within the backup, the near plane stays
        // at or beyond it (<= residentNearZ) so no resident caster is clipped.
        for residentNearZ in stride(from: Float(-900), through: -20, by: 55) {
            let near = ShadowCascadeMath.clampedShadowNearZ(
                sliceNearZ: -10,
                fullBackupNearZ: -1000,
                residentNearZ: residentNearZ
            )
            #expect(near <= residentNearZ + 1e-3)
            #expect(near <= -10, "slice must stay covered")
        }
    }

    @Test func clampKeepsFullBackupWhenResidentReachesFurther() {
        // Resident geometry extends past the backup toward the sun: keep the
        // original 7.1.1 near (backup already limits reach), never extend more.
        let near = ShadowCascadeMath.clampedShadowNearZ(
            sliceNearZ: -10,
            fullBackupNearZ: -1000,
            residentNearZ: -5000
        )
        #expect(near == -1000)
    }

    @Test func clampNilResidentIsUnclamped() {
        let near = ShadowCascadeMath.clampedShadowNearZ(
            sliceNearZ: -10,
            fullBackupNearZ: -1000,
            residentNearZ: nil
        )
        #expect(near == -1000)
    }

    @Test func clampCapsAtSliceWhenResidentBehindSlice() {
        // Resident geometry all sits behind the slice near (none toward the
        // sun): no backup needed, near collapses to the slice near.
        let near = ShadowCascadeMath.clampedShadowNearZ(
            sliceNearZ: -10,
            fullBackupNearZ: -1000,
            residentNearZ: 50
        )
        #expect(near == -10)
    }

    @Test func clampDegenerateResidentBoundsAreFinite() {
        // A zero-volume (point) resident AABB must still yield a finite near.
        let point = ModelBounds(min: SIMD3(3, 4, 5), max: SIMD3(3, 4, 5))
        let lightView = MatrixMath.lookAt(
            eye: SIMD3(3, 4, 105),
            target: SIMD3(3, 4, 5),
            up: SIMD3(1, 0, 0)
        )
        let residentNearZ = ShadowCascadeMath.residentNearLightZ(point, lightView: lightView)
        let near = ShadowCascadeMath.clampedShadowNearZ(
            sliceNearZ: -10,
            fullBackupNearZ: -1000,
            residentNearZ: residentNearZ
        )
        #expect(near.isFinite)
    }

    // MARK: - end-to-end cascade fit

    private static let fovY: Float = .pi / 3
    private static let aspect: Float = 16.0 / 9.0
    private static let nearPlane: Float = 1
    private static let shadowDistance: Float = 200
    private static let resolution = 2048
    private static let casterBackup: Float = 40
    private static let cameraToWorld = MatrixMath.translation(SIMD3<Float>(120, -60, 400))
    private static let sun = SIMD3<Float>(0, 0, -1)

    private func makeCascades(residentBounds: ModelBounds?) -> [ShadowCascade] {
        ShadowCascadeMath.makeCascades(
            cameraToWorld: Self.cameraToWorld,
            fovYRadians: Self.fovY,
            aspectRatio: Self.aspect,
            nearPlane: Self.nearPlane,
            shadowDistance: Self.shadowDistance,
            sunDirection: Self.sun,
            cascadeCount: 3,
            lambda: 0.6,
            shadowMapResolution: Self.resolution,
            casterBackup: Self.casterBackup,
            residentBounds: residentBounds
        )
    }

    @Test func residentBoundsClampNeverWidensAndShrinksSomeCascade() {
        // A resident AABB that hugs the frustum slices must not widen any
        // cascade's light Z range versus the unclamped fit, and must strictly
        // shrink at least one (the far cascades over-extend most).
        let residentBounds = ModelBounds(min: SIMD3(-400, -400, -50), max: SIMD3(400, 400, 50))
        let unclamped = makeCascades(residentBounds: nil)
        let clamped = makeCascades(residentBounds: residentBounds)
        var shrunkAny = false
        for (base, tight) in zip(unclamped, clamped) {
            #expect(Self.zRange(tight) <= Self.zRange(base) + 1e-2)
            if Self.zRange(tight) < Self.zRange(base) - 1e-2 {
                shrunkAny = true
            }
        }
        #expect(shrunkAny, "resident clamp must shrink at least one cascade")
    }

    /// Light-space depth range a cascade spans, recovered by peeling the light
    /// view off the viewProjection to isolate the ortho matrix (its m22 =
    /// -1/(far-near)). The light view is rebuilt from the slice geometry the
    /// same way fitCascade does.
    private static func zRange(_ cascade: ShadowCascade) -> Float {
        let sun = ShadowCascadeMath.normalizedSun(Self.sun)
        let up = ShadowCascadeMath.lightUp(sun)
        let corners = ShadowCascadeMath.sliceCorners(
            cameraToWorld: cameraToWorld,
            tanHalfFovY: tanf(fovY * 0.5),
            aspectRatio: aspect,
            sliceNear: cascade.splitNear,
            sliceFar: cascade.splitFar
        )
        let sphere = ShadowCascadeMath.boundingSphere(corners)
        let lightView = MatrixMath.lookAt(
            eye: sphere.center - sun * sphere.radius,
            target: sphere.center,
            up: up
        )
        let ortho = cascade.viewProjection * lightView.inverse
        return 1 / abs(ortho.columns.2.z)
    }
}
