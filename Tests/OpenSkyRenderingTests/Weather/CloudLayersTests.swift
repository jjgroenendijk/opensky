// Cloud layer resolve over a synthetic WTHR record: textures, tint, opacity, drift,
// the disabled and LNAM limits, and the transition fade.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyRendering
import simd
import Testing

struct CloudLayersTests {
    @Test func speedByteCentresOnStill() {
        #expect(ResolvedCloudLayer.speed(127) == 0)
        #expect(abs(ResolvedCloudLayer.speed(254) - 0.1) < 1e-6)
        #expect(abs(ResolvedCloudLayer.speed(0) + 0.1) < 1e-6)
        #expect(ResolvedCloudLayer.speed(nil) == 0)
    }

    @Test func layersCarryTextureTintAlphaAndDrift() throws {
        let weather = try Self.weather()
        let noon = TimeOfDayWeights(hour: 12, timing: nil)
        let layers = ResolvedCloudLayer.layers(of: weather.sky, weights: noon)
        // Layer 5 is disabled in NAM1, layer 30 is past LNAM 29.
        #expect(layers.map(\.layer) == [0, 3])
        let first = try #require(layers.first)
        #expect(first.texture == "Sky\\Upper.dds")
        #expect(first.color == SIMD3(1, 0, 0))
        #expect(first.alpha == 0.5)
        #expect(first.velocity.x == 0)
        #expect(abs(first.velocity.y - 0.1) < 1e-6)
    }

    @Test func nightPicksTheNightKeyframe() throws {
        let weather = try Self.weather()
        let midnight = TimeOfDayWeights(hour: 0, timing: nil)
        let first = try #require(ResolvedCloudLayer.layers(of: weather.sky, weights: midnight)
            .first)
        #expect(first.color == SIMD3(0, 0, 1))
        #expect(first.alpha == 0.25)
    }

    @Test func transitionFadesBothWeathersLayers() throws {
        let resolved = try ResolvedWeather.resolve(Self.weather(), hour: 12, timing: nil)
        let blend = ResolvedWeather.blend(resolved, resolved, 0.25)
        #expect(blend.clouds.count == 4)
        #expect(blend.clouds[0].alpha == 0.5 * 0.75)
        #expect(blend.clouds[2].alpha == 0.5 * 0.25)
    }

    @Test func offsetWrapsToOneRepeat() {
        let offset = Renderer.cloudOffset(SIMD2(0.1, -0.1), seconds: 25)
        #expect(abs(offset.x - 0.5) < 1e-4)
        #expect(abs(offset.y - 0.5) < 1e-4)
    }

    @Test func domeKeepsShapeOrderAndRebasesIndices() {
        let shape = { (offset: Float) in
            Mesh(
                name: nil, transform: matrix_identity_float4x4,
                positions: [SIMD3(offset, 0, 0), SIMD3(offset, 1, 0), SIMD3(offset, 0, 1)],
                normals: [], tangents: [], bitangents: [], uvs: [], colors: [],
                indices: [0, 1, 2], materialSlot: 0
            )
        }
        let model = Model(meshes: [shape(0), shape(5)], materials: [], skippedShapeCount: 0)
        let dome = CloudDomeGeometry(model: model)
        #expect(dome.shapes == [0 ..< 3, 3 ..< 6])
        #expect(dome.indices == [0, 1, 2, 3, 4, 5])
        #expect(dome.positions[3].x == 5)
        #expect(dome.colors.allSatisfy { $0 == SIMD4(1, 1, 1, 1) })
    }

    // MARK: - Fixture

    private static func weather() throws -> Weather {
        let texture = { (path: String) in ESMFixture.zstring(path) }
        var speedY = Data(repeating: 127, count: 32)
        speedY[0] = 254
        var colors = Data(count: 512)
        var alphas = Data(count: 512)
        for layer in 0 ..< 32 {
            // Sunrise, day, sunset, night: day red, night blue.
            colors.replaceSubrange(layer * 16 ..< layer * 16 + 16, with: [
                0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 0
            ])
            for (slot, value) in [Float(1), 0.5, 1, 0.25].enumerated() {
                withUnsafeBytes(of: value.bitPattern.littleEndian) {
                    alphas.replaceSubrange(
                        layer * 16 + slot * 4 ..< layer * 16 + slot * 4 + 4,
                        with: $0
                    )
                }
            }
        }
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("CloudTest"))
        let textures = [
            ("00TX", "Sky\\Upper.dds"), ("30TX", "Sky\\Lower.dds"),
            ("50TX", "Sky\\Off.dds"), ("N0TX", "Sky\\Past.dds")
        ]
        for (signature, path) in textures {
            fields += ESMFixture.field(signature, texture(path))
        }
        fields += ESMFixture.field("LNAM", Self.uint32(29))
        fields += ESMFixture.field("RNAM", speedY)
        fields += ESMFixture.field("QNAM", Data(repeating: 127, count: 32))
        fields += ESMFixture.field("PNAM", colors)
        fields += ESMFixture.field("JNAM", alphas)
        fields += ESMFixture.field("NAM1", Self.uint32(1 << 5))
        let record = ESMFixture.record("WTHR", formID: 0x900, data: fields)
        let plugin = ESMFixture.tes4() + ESMFixture.topGroup("WTHR", contents: record)
        let store = try WeatherStore(file: ESMFile(data: plugin))
        let weather = store.weather(FormID(0x900))
        return try #require(weather)
    }

    private static func uint32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
