// Far shadow cascades keep their map while it covers the view, the sun stays put,
// and the map is young; the first cascade is drawn every frame.

@testable import OpenSkyFormatsCore
@testable import OpenSkyRenderCore
import simd
import Testing

struct ShadowCascadeReuseTests {
    private static func request(
        at position: SIMD3<Float> = SIMD3(120, -60, 400),
        sun: SIMD3<Float> = SIMD3(0.3, 0.2, -1)
    ) -> ShadowCascadeRequest {
        var request = ShadowCascadeRequest(
            cameraToWorld: MatrixMath.translation(position),
            fovYRadians: .pi / 3,
            aspectRatio: 16.0 / 9.0,
            nearPlane: 1,
            shadowDistance: 2000,
            sunDirection: sun,
            cascadeCount: 3,
            lambda: 0.6,
            shadowMapResolution: 2048,
            casterBackup: 40
        )
        request.farCascadeMargin = ShadowCascadeReuse.margin
        return request
    }

    private static func plan(
        _ reuse: inout ShadowCascadeReuse, _ request: ShadowCascadeRequest
    ) -> ShadowCascadePlan {
        reuse.plan(request, fresh: ShadowCascadeMath.makeCascades(request))
    }

    @Test func aStillCameraRedrawsEachFarCascadeAtItsAgeLimit() {
        var reuse = ShadowCascadeReuse()
        var drawn: [[Bool]] = []
        for _ in 0 ..< 5 {
            drawn.append(Self.plan(&reuse, Self.request()).redraws)
        }
        #expect(drawn == [
            [true, true, true],
            [true, false, false],
            [true, true, false],
            [true, false, false],
            [true, true, true]
        ])
    }

    @Test func aKeptCascadeKeepsTheTransformItWasDrawnWith() {
        var reuse = ShadowCascadeReuse()
        let first = Self.plan(&reuse, Self.request())
        let moved = Self.request(at: SIMD3(124, -60, 400))
        let second = Self.plan(&reuse, moved)

        #expect(second.redraws == [true, false, false])
        #expect(second.cascades[2].viewProjection == first.cascades[2].viewProjection)
        let fresh = ShadowCascadeMath.makeCascades(moved)
        #expect(second.cascades[0].viewProjection == fresh[0].viewProjection)
        #expect(second.cascades[2].splitFar == fresh[2].splitFar)
    }

    @Test func aViewOutsideTheOldMapOrATurnedSunDrawsAgain() {
        var reuse = ShadowCascadeReuse()
        _ = Self.plan(&reuse, Self.request())
        let far = Self.plan(&reuse, Self.request(at: SIMD3(3000, -60, 400)))
        #expect(far.redraws == [true, true, true])

        let turned = Self.plan(
            &reuse, Self.request(at: SIMD3(3000, -60, 400), sun: SIMD3(0.4, 0.2, -1))
        )
        #expect(turned.redraws == [true, true, true])
    }

    @Test func aResetDrawsEveryCascade() {
        var reuse = ShadowCascadeReuse()
        _ = Self.plan(&reuse, Self.request())
        reuse.reset()
        #expect(Self.plan(&reuse, Self.request()).redraws == [true, true, true])
    }

    @Test func theMarginWidensOnlyTheFarCascades() {
        var tight = Self.request()
        tight.farCascadeMargin = 0
        let plain = ShadowCascadeMath.makeCascades(tight)
        let wide = ShadowCascadeMath.makeCascades(Self.request())
        #expect(plain[0].viewProjection == wide[0].viewProjection)
        // A wider square maps the same world size to a smaller clip size.
        #expect(Self.clipScale(wide[2]) < Self.clipScale(plain[2]))
    }

    /// Clip x per world unit: the length of the transform's first row.
    private static func clipScale(_ cascade: ShadowCascade) -> Float {
        let matrix = cascade.viewProjection
        return simd_length(SIMD3(matrix.columns.0.x, matrix.columns.1.x, matrix.columns.2.x))
    }
}
