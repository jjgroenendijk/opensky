// The SPGD-to-precipitation mapping: rain and snow scales against their
// anchors, the clamp, and the fallback.

import FormatsESMTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyRendering
import Testing

struct PrecipitationTuningTests {
    private typealias Fixture = ESMFixture

    static func geometry(
        type: UInt32, gravity: Float, size: SIMD2<Float>, density: Float
    ) throws -> ShaderParticleGeometry {
        let data = Fixture.f32(gravity, 0, size.x, size.y, 0, 0, 0) + Fixture.u32(1, 1, type)
            + Fixture.u32(5000) + Fixture.f32(density)
        return try ShaderParticleGeometry(record: Fixture.record("SPGD", fields: [
            ("EDID", Fixture.zstring("TestRain")), ("DATA", data)
        ]))
    }

    @Test func theVanillaRainRecordKeepsTheHandTunedLook() throws {
        let tuning = try PrecipitationTuning(record: Self.geometry(
            type: 0, gravity: 675, size: SIMD2(0.35, 2), density: 1
        ))
        #expect(tuning.rain == .identity)
        #expect(tuning.snow == .identity)
        #expect(tuning.source == "TestRain")
    }

    @Test func aHeavierRainRecordScalesSpeedSizeAndDensity() throws {
        let tuning = try PrecipitationTuning(record: Self.geometry(
            type: 0, gravity: 1350, size: SIMD2(1.4, 2), density: 2
        ))
        #expect(tuning.rain.speed == 2)
        #expect(tuning.rain.size == 2)
        #expect(tuning.rain.density == 2)
    }

    @Test func snowFeedsTheSnowVolumeAndClamps() throws {
        let tuning = try PrecipitationTuning(record: Self.geometry(
            type: 1, gravity: 10000, size: SIMD2(1, 1), density: 3
        ))
        #expect(tuning.rain == .identity)
        #expect(tuning.snow.speed == PrecipitationScale.range.upperBound)
        #expect(tuning.snow.density == 1)
    }

    @Test func noRecordOrAnUnknownTypeIsTheFallback() throws {
        #expect(PrecipitationTuning(record: nil) == .fallback)
        let odd = try Self.geometry(type: 7, gravity: 1, size: SIMD2(1, 1), density: 1)
        #expect(PrecipitationTuning(record: odd) == .fallback)
    }

    @Test func theReadoutShowsFallbackNextToDerived() throws {
        let tuning = try PrecipitationTuning(record: Self.geometry(
            type: 0, gravity: 1350, size: SIMD2(0.35, 2), density: 1
        ))
        #expect(tuning.readoutLines[0] == "Source: TestRain")
        #expect(tuning.readoutLines[1] == "Rain: speed 1900 → 3800 · size 12 → 12 · density × 1.00")
    }
}
