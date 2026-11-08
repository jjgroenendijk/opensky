// The mean colour of a cell's land: base textures, painted layers, and VCLR.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyRenderCore
import simd
import Testing

struct TerrainCellAlbedoTests {
    private let grey = FormID(0x10)
    private let white = FormID(0x20)

    private func mean(_ id: FormID) -> SIMD3<Float>? {
        switch id {
        case grey: SIMD3(repeating: 0.2)
        case white: SIMD3(repeating: 1)
        default: nil
        }
    }

    @Test func baseTextureTimesVertexColour() throws {
        let land = try landRecord(base: grey, vertexColour: 128)
        let albedo = try #require(TerrainCellAlbedo.mean(land: land, textureMean: mean))
        #expect(abs(albedo.x - 0.2 * 128 / 255) < 0.0001)
    }

    @Test func layerBlendsOverItsQuadrant() throws {
        // Quadrant 0 fully white over grey: a quarter of the cell turns white.
        let land = try landRecord(base: grey, layer: white, opacity: 1)
        let albedo = try #require(TerrainCellAlbedo.mean(land: land, textureMean: mean))
        #expect(abs(albedo.x - (0.25 * 1 + 0.75 * 0.2)) < 0.0001)
    }

    @Test func unpaintedOrUnresolvedCellGivesNothing() throws {
        #expect(try TerrainCellAlbedo.mean(land: landRecord(base: nil), textureMean: mean) == nil)
        let unknown = try landRecord(base: FormID(0x99))
        #expect(TerrainCellAlbedo.mean(land: unknown, textureMean: mean) == nil)
    }

    private func landRecord(
        base: FormID?,
        layer: FormID? = nil,
        opacity: Float = 0,
        vertexColour: UInt8? = nil
    ) throws -> Land {
        var fields = Data()
        if let vertexColour {
            fields += ESMFixture.field(
                "VCLR",
                Data(repeating: vertexColour, count: Land.vertexCount * 3)
            )
        }
        for quadrant in UInt8(0) ... 3 {
            if let base {
                fields += ESMFixture.field("BTXT", header(base, quadrant: quadrant, layer: 0))
            }
        }
        if let layer {
            fields += ESMFixture.field("ATXT", header(layer, quadrant: 0, layer: 0))
            var alphas = Data()
            for position in UInt16(0) ..< 289 {
                alphas.appendUInt16(position)
                alphas.appendUInt16(0)
                alphas.appendFloat32(opacity)
            }
            fields += ESMFixture.field("VTXT", alphas)
        }
        return try Land(record: ESMFixture.parseRecord(ESMFixture.record("LAND", data: fields)))
    }

    private func header(_ texture: FormID, quadrant: UInt8, layer: Int16) -> Data {
        var data = Data()
        data.appendUInt32(texture.rawValue)
        data.append(contentsOf: [quadrant, 0])
        data.appendUInt16(UInt16(bitPattern: layer))
        return data
    }
}
