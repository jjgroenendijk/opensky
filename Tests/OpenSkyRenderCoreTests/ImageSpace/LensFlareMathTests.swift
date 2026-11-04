// The sun's screen position for the lens flare.

@testable import OpenSkyRenderCore
import simd
import Testing

struct LensFlareMathTests {
    /// Looks along +y from the origin with z up, in a right-handed 0-to-1 depth projection.
    static let viewProjection: float4x4 = {
        let view = float4x4(
            SIMD4(1, 0, 0, 0), SIMD4(0, 0, -1, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 0, 1)
        )
        let near: Float = 1
        let far: Float = 1_000_000
        let projection = float4x4(
            SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0),
            SIMD4(0, 0, far / (near - far), -1), SIMD4(0, 0, near * far / (near - far), 0)
        )
        return projection * view
    }()

    @Test func aSunAheadSitsAtTheCentre() throws {
        let position = try #require(LensFlareMath.sunScreenPosition(
            viewProjection: Self.viewProjection, camera: .zero, toSun: SIMD3(0, 1, 0.0001)
        ))
        #expect(abs(position.x - 0.5) < 1.0e-3)
        #expect(abs(position.y - 0.5) < 1.0e-3)
    }

    @Test func aHigherSunSitsHigherOnTheScreen() throws {
        let position = try #require(LensFlareMath.sunScreenPosition(
            viewProjection: Self.viewProjection, camera: .zero, toSun: SIMD3(0, 1, 0.5)
        ))
        #expect(position.y < 0.5)
    }

    @Test func aSunBehindOrBelowHasNoPosition() {
        #expect(LensFlareMath.sunScreenPosition(
            viewProjection: Self.viewProjection, camera: .zero, toSun: SIMD3(0, -1, 0.2)
        ) == nil)
        #expect(LensFlareMath.sunScreenPosition(
            viewProjection: Self.viewProjection, camera: .zero, toSun: SIMD3(0, 1, -0.2)
        ) == nil)
    }
}
