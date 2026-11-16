// A MATO record turned into the directional material a static's shapes take.

import Foundation
@testable import OpenSkyCells
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
import Testing

struct DirectionalMaterialTests {
    /// A 52-byte `DATA`: falloff scale and bias, noise and material UV scale, projection
    /// vector, normal dampener, single-pass colour, single-pass flag, snow flag.
    private static func properties(singlePass: Bool) throws -> MaterialObject.Properties {
        var data = ESMFixture.f32([0.35, 0.4, 48, 256, 0, 0, -1, 0.75, 0.5, 0.5, 0.5])
        data.appendUInt32(singlePass ? 1 : 0)
        data.appendUInt32(1)
        let record = try ESMFixture.record("MATO", fields: [("DATA", data)])
        return try #require(MaterialObject(record: record).properties)
    }

    @Test func anOverlayLiesAgainstItsProjectionVector() throws {
        let overlay = try CellSceneBuilder.CellObjectBuilder.projectedMaterial(
            Self.properties(singlePass: false), maxAngle: 60, overlayTexture: "moss.dds"
        )
        #expect(overlay.direction == SIMD3(0, 0, 1))
        #expect(overlay.diffuseTexture == "moss.dds")
        #expect(overlay.normalDampener == 0.75)
        #expect(overlay.isSnow)
        #expect(!overlay.singlePass)
    }

    @Test func aSinglePassMaterialUsesTheSharedMapsStraightDown() throws {
        let layer = try CellSceneBuilder.CellObjectBuilder.projectedMaterial(
            Self.properties(singlePass: true), maxAngle: 60, overlayTexture: nil
        )
        #expect(layer.direction == SIMD3(0, 0, 1))
        #expect(layer.diffuseTexture == "textures\\effects\\projecteddiffuse.dds")
        #expect(layer.singlePass)
    }
}
