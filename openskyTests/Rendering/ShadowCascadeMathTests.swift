// Unit tests for ShadowCascadeMath + MatrixMath.orthographic (AGENTS.md
// "Testing": every math routine tested with synthetic in-code fixtures).

@testable import opensky
import simd
import Testing

struct ShadowCascadeMathTests {
    // MARK: - splitDistances

    @Test func splitDistancesAreStrictlyIncreasing() {
        let splits = ShadowCascadeMath.splitDistances(near: 1, far: 500, count: 4, lambda: 0.7)
        #expect(splits.count == 4)
        for pair in zip(splits, splits.dropFirst()) {
            #expect(pair.0 < pair.1)
        }
    }

    @Test func splitDistancesPinEndpoints() {
        let near: Float = 2
        let far: Float = 300
        let splits = ShadowCascadeMath.splitDistances(near: near, far: far, count: 3, lambda: 0.5)
        #expect(splits.first ?? 0 > near)
        #expect(abs((splits.last ?? 0) - far) < 1e-3)
    }

    @Test func splitDistancesLambdaZeroIsUniform() {
        let near: Float = 1
        let far: Float = 100
        let count = 4
        let splits = ShadowCascadeMath.splitDistances(
            near: near,
            far: far,
            count: count,
            lambda: 0
        )
        for index in 1 ... count {
            let expected = near + (far - near) * Float(index) / Float(count)
            #expect(abs(splits[index - 1] - expected) < 1e-2)
        }
    }

    @Test func splitDistancesLambdaOneIsLogarithmic() {
        let near: Float = 1
        let far: Float = 1000
        let count = 4
        let splits = ShadowCascadeMath.splitDistances(
            near: near,
            far: far,
            count: count,
            lambda: 1
        )
        for index in 1 ... count {
            let expected = near * powf(far / near, Float(index) / Float(count))
            #expect(abs(splits[index - 1] - expected) < 1e-1)
        }
    }

    @Test func splitDistancesCountOne() {
        let splits = ShadowCascadeMath.splitDistances(near: 1, far: 250, count: 1, lambda: 0.5)
        #expect(splits.count == 1)
        #expect(abs((splits.first ?? 0) - 250) < 1e-3)
    }

    @Test func splitDistancesDegenerateInputDoesNotCrash() {
        // far < near and count < 1 both clamp to a sane, increasing result.
        let splits = ShadowCascadeMath.splitDistances(near: 100, far: 10, count: 0, lambda: 0.5)
        #expect(splits.count == 1)
        #expect((splits.first ?? 0).isFinite)
    }

    // MARK: - orthographic

    @Test func orthographicMapsCenterToNdcOrigin() {
        let ortho = MatrixMath.orthographic(
            left: -10,
            right: 30,
            bottom: -4,
            top: 16,
            nearZ: 1,
            farZ: 100
        )
        let center = ortho * SIMD4<Float>(10, 6, -50.5, 1)
        #expect(abs(center.x / center.w) < 1e-5)
        #expect(abs(center.y / center.w) < 1e-5)
    }

    @Test func orthographicMapsEdgesToNdcCorners() {
        let ortho = MatrixMath.orthographic(
            left: -2,
            right: 6,
            bottom: -3,
            top: 5,
            nearZ: 1,
            farZ: 50
        )
        let low = ortho * SIMD4<Float>(-2, -3, -1, 1)
        let high = ortho * SIMD4<Float>(6, 5, -1, 1)
        #expect(abs(low.x + 1) < 1e-5)
        #expect(abs(low.y + 1) < 1e-5)
        #expect(abs(high.x - 1) < 1e-5)
        #expect(abs(high.y - 1) < 1e-5)
    }

    @Test func orthographicMapsNearToZeroAndFarToOne() {
        let ortho = MatrixMath.orthographic(
            left: -1,
            right: 1,
            bottom: -1,
            top: 1,
            nearZ: 0.5,
            farZ: 200
        )
        let near = ortho * SIMD4<Float>(0, 0, -0.5, 1)
        let far = ortho * SIMD4<Float>(0, 0, -200, 1)
        #expect(abs(near.z / near.w) < 1e-5)
        #expect(abs(far.z / far.w - 1) < 1e-5)
    }

    // MARK: - makeCascades

    private static let fovY: Float = .pi / 3
    private static let aspect: Float = 16.0 / 9.0
    private static let nearPlane: Float = 1
    private static let shadowDistance: Float = 200
    private static let resolution = 2048
    private static let casterBackup: Float = 40
    // Camera above the world looking straight down -Z; sun travels straight down.
    private static let cameraToWorld = MatrixMath.translation(SIMD3<Float>(120, -60, 400))
    private static let sun = SIMD3<Float>(0, 0, -1)

    private func cascades(cameraToWorld: simd_float4x4 = Self.cameraToWorld) -> [ShadowCascade] {
        ShadowCascadeMath.makeCascades(
            cameraToWorld: cameraToWorld,
            fovYRadians: Self.fovY,
            aspectRatio: Self.aspect,
            nearPlane: Self.nearPlane,
            shadowDistance: Self.shadowDistance,
            sunDirection: Self.sun,
            cascadeCount: 3,
            lambda: 0.6,
            shadowMapResolution: Self.resolution,
            casterBackup: Self.casterBackup
        )
    }

    private func sliceCorners(for cascade: ShadowCascade) -> [SIMD3<Float>] {
        ShadowCascadeMath.sliceCorners(
            cameraToWorld: Self.cameraToWorld,
            tanHalfFovY: tanf(Self.fovY * 0.5),
            aspectRatio: Self.aspect,
            sliceNear: cascade.splitNear,
            sliceFar: cascade.splitFar
        )
    }

    @Test func makeCascadesSplitBoundsChainAndCoverRange() {
        let result = cascades()
        #expect(result.count == 3)
        #expect(abs(result[0].splitNear - Self.nearPlane) < 1e-4)
        #expect(abs((result.last?.splitFar ?? 0) - Self.shadowDistance) < 1e-3)
        for pair in zip(result, result.dropFirst()) {
            #expect(abs(pair.0.splitFar - pair.1.splitNear) < 1e-4)
        }
    }

    @Test func makeCascadesEncloseSliceCornersInNdc() {
        for cascade in cascades() {
            for corner in sliceCorners(for: cascade) {
                let clip = cascade.viewProjection * SIMD4<Float>(corner.x, corner.y, corner.z, 1)
                let ndc = SIMD3<Float>(clip.x, clip.y, clip.z) / clip.w
                #expect(ndc.x >= -1.0001 && ndc.x <= 1.0001)
                #expect(ndc.y >= -1.0001 && ndc.y <= 1.0001)
                #expect(ndc.z >= -0.0001 && ndc.z <= 1.0001)
            }
        }
    }

    @Test func makeCascadesKeepCastersTowardSunInFront() {
        // A caster between the sun and the slice (within casterBackup) must not
        // fall behind the light near plane: clip z stays >= 0.
        let towardSun = -Self.sun * (Self.casterBackup * 0.5)
        for cascade in cascades() {
            for corner in sliceCorners(for: cascade) {
                let moved = corner + towardSun
                let clip = cascade.viewProjection * SIMD4<Float>(moved.x, moved.y, moved.z, 1)
                #expect(clip.z / clip.w >= -1e-3)
            }
        }
    }

    @Test func makeCascadesProduceFiniteMatricesForStraightDownSun() {
        for cascade in cascades() {
            for column in 0 ..< 4 {
                #expect(cascade.viewProjection[column].x.isFinite)
                #expect(cascade.viewProjection[column].y.isFinite)
                #expect(cascade.viewProjection[column].z.isFinite)
                #expect(cascade.viewProjection[column].w.isFinite)
            }
        }
    }

    // MARK: - texel snapping

    private struct OrthoOrigin {
        var left: Float
        var bottom: Float
        var texel: Float
    }

    /// Reconstruct a cascade's ortho origin (left, bottom) in light space and
    /// the light-space texel size, from the public viewProjection.
    private func orthoOrigin(
        for cascade: ShadowCascade,
        cameraToWorld: simd_float4x4
    ) -> OrthoOrigin {
        let sun = ShadowCascadeMath.normalizedSun(Self.sun)
        let up = ShadowCascadeMath.lightUp(sun)
        let corners = ShadowCascadeMath.sliceCorners(
            cameraToWorld: cameraToWorld,
            tanHalfFovY: tanf(Self.fovY * 0.5),
            aspectRatio: Self.aspect,
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
        let left = (-ortho.columns.3.x - 1) / ortho.columns.0.x
        let bottom = (-ortho.columns.3.y - 1) / ortho.columns.1.y
        let texel = 2 * sphere.radius / Float(Self.resolution)
        return OrthoOrigin(left: left, bottom: bottom, texel: texel)
    }

    @Test func orthoOriginLandsOnTexelGrid() {
        let cascade = cascades()[1]
        let origin = orthoOrigin(for: cascade, cameraToWorld: Self.cameraToWorld)
        let stepsX = origin.left / origin.texel
        let stepsY = origin.bottom / origin.texel
        #expect(abs(stepsX - stepsX.rounded()) < 1e-2)
        #expect(abs(stepsY - stepsY.rounded()) < 1e-2)
    }

    @Test func subTexelCameraShiftMovesOriginByWholeTexels() {
        // Tiny world offset must not shimmer the origin: it stays identical or
        // jumps by an exact multiple of the texel size.
        let offset = MatrixMath.translation(SIMD3<Float>(0.3, -0.2, 0))
        let shifted = offset * Self.cameraToWorld
        let baseCascades = cascades()
        let shiftedCascades = cascades(cameraToWorld: shifted)
        let base = orthoOrigin(for: baseCascades[1], cameraToWorld: Self.cameraToWorld)
        let moved = orthoOrigin(for: shiftedCascades[1], cameraToWorld: shifted)
        let deltaSteps = (moved.left - base.left) / base.texel
        #expect(abs(deltaSteps - deltaSteps.rounded()) < 1e-2)
    }

    // MARK: - lightUp switch

    @Test func lightUpSwitchesWhenSunIsVertical() {
        #expect(ShadowCascadeMath.lightUp(SIMD3<Float>(0, 0, -1)) == SIMD3<Float>(1, 0, 0))
        #expect(ShadowCascadeMath.lightUp(SIMD3<Float>(0, 0, 1)) == SIMD3<Float>(1, 0, 0))
        #expect(ShadowCascadeMath.lightUp(SIMD3<Float>(0, 1, 0)) == SIMD3<Float>(0, 0, 1))
        let slanted = simd_normalize(SIMD3<Float>(0.4, 0.3, -0.8))
        #expect(ShadowCascadeMath.lightUp(slanted) == SIMD3<Float>(0, 0, 1))
    }

    // MARK: - cascadeIndex

    @Test func cascadeIndexSelectsFirstContainingSlice() {
        let splits = SIMD4<Float>(10, 20, 30, 40)
        #expect(ShadowCascadeMath.cascadeIndex(viewDepth: 5, splits: splits, cascadeCount: 4) == 0)
        #expect(ShadowCascadeMath.cascadeIndex(viewDepth: 15, splits: splits, cascadeCount: 4) == 1)
        #expect(ShadowCascadeMath.cascadeIndex(viewDepth: 25, splits: splits, cascadeCount: 4) == 2)
        #expect(ShadowCascadeMath.cascadeIndex(viewDepth: 35, splits: splits, cascadeCount: 4) == 3)
    }

    @Test func cascadeIndexIsInclusiveAtBoundaries() {
        let splits = SIMD4<Float>(10, 20, 30, 40)
        #expect(ShadowCascadeMath.cascadeIndex(viewDepth: 10, splits: splits, cascadeCount: 4) == 0)
        #expect(ShadowCascadeMath.cascadeIndex(viewDepth: 20, splits: splits, cascadeCount: 4) == 1)
    }

    @Test func cascadeIndexClampsBeyondFarToLast() {
        let splits = SIMD4<Float>(10, 20, 30, 40)
        #expect(ShadowCascadeMath
            .cascadeIndex(viewDepth: 999, splits: splits, cascadeCount: 4) == 3)
    }

    @Test func cascadeIndexIgnoresPaddingEntries() {
        // cascadeCount 2: entries 2..3 are padding (== last real bound).
        let splits = SIMD4<Float>(10, 20, 20, 20)
        #expect(ShadowCascadeMath.cascadeIndex(viewDepth: 5, splits: splits, cascadeCount: 2) == 0)
        #expect(ShadowCascadeMath.cascadeIndex(viewDepth: 15, splits: splits, cascadeCount: 2) == 1)
        #expect(ShadowCascadeMath.cascadeIndex(viewDepth: 25, splits: splits, cascadeCount: 2) == 1)
    }
}
