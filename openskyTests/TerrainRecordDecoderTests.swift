// Terrain record decoder tests (LAND, LTEX, TXST) over synthetic in-code
// records (ESMFixture) — never extracted game files (AGENTS.md "Legal & IP
// boundary"). Layouts: UESP "Skyrim Mod:Mod File Format" LAND/LTEX/TXST +
// xEdit wbDefinitionsCommon.pas; see docs/formats/land.md.

import Foundation
@testable import opensky
import simd
import Testing

struct TerrainRecordDecoderTests {
    /// Parses one synthetic record through the container walk.
    private func record(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }

    // MARK: - VHGT fixture

    /// A single non-zero VHGT delta at (row, col).
    private struct Delta {
        let row: Int
        let col: Int
        let value: Int8
    }

    /// 1096-byte VHGT: anchor float, 33x33 int8 deltas, 3 unused bytes. Only
    /// the listed (row, col) deltas are non-zero.
    private func vhgt(anchor: Float, deltas: [Delta]) -> Data {
        var bytes = [UInt8](repeating: 0, count: Land.vertexCount)
        for delta in deltas {
            bytes[delta.row * Land.dimension + delta.col] = UInt8(bitPattern: delta.value)
        }
        var data = Data()
        data.appendFloat32(anchor)
        data.append(contentsOf: bytes)
        data.append(contentsOf: [0, 0, 0]) // 3 unused
        return data
    }

    /// 8-byte BTXT/ATXT header.
    private func textureHeader(texture: UInt32, quadrant: UInt8, layer: Int16) -> Data {
        var data = Data()
        data.appendUInt32(texture)
        data.append(quadrant)
        data.append(0) // unused
        data.appendUInt16(UInt16(bitPattern: layer))
        return data
    }

    /// VTXT: 8-byte entries { uint16 position, uint16 unused, float32 opacity }.
    private func vtxt(_ samples: [(position: UInt16, opacity: Float)]) -> Data {
        var data = Data()
        for sample in samples {
            data.appendUInt16(sample.position)
            data.appendUInt16(0) // unused
            data.appendFloat32(sample.opacity)
        }
        return data
    }

    // MARK: - LAND height field

    @Test func decodesVHGTDeltaAccumulation() throws {
        // Column 0 carries a running vertical offset (row 0 from the anchor);
        // columns 1-32 accumulate west->east from column 0. Final height = *8.
        // anchor 10; col0 running: 10+1=11 (r0), 11+5=16 (r1), 16-6=10 (r2).
        let field = ESMFixture.field("VHGT", vhgt(anchor: 10, deltas: [
            Delta(row: 0, col: 0, value: 1), Delta(row: 0, col: 1, value: 2),
            Delta(row: 0, col: 2, value: -3),
            Delta(row: 1, col: 0, value: 5), Delta(row: 1, col: 1, value: -4),
            Delta(row: 2, col: 0, value: -6)
        ]))
        let land = try Land(record: record(ESMFixture.record("LAND", data: field)))
        let heights = try #require(land.heightField?.heights)
        #expect(land.heightField?.anchor == 10)
        #expect(heights.count == Land.vertexCount)
        func height(_ row: Int, _ col: Int) -> Float {
            heights[row * Land.dimension + col]
        }
        // Row 0: 11, 13, 10, then 10 to the edge — all *8.
        #expect(height(0, 0) == 88)
        #expect(height(0, 1) == 104)
        #expect(height(0, 2) == 80)
        #expect(height(0, 32) == 80)
        // Row 1: col0 16, col1 12, holds 12 east — *8.
        #expect(height(1, 0) == 128)
        #expect(height(1, 1) == 96)
        #expect(height(1, 32) == 96)
        // Row 2: col0 back to 10 via the -6 vertical delta.
        #expect(height(2, 0) == 80)
        // Rows past the edits inherit the row-2 column-0 value (10).
        #expect(height(32, 0) == 80)
        #expect(height(32, 32) == 80)
    }

    // MARK: - LAND normals + colors

    @Test func decodesVNML() throws {
        var bytes = [UInt8](repeating: 0, count: Land.vertexCount * 3)
        bytes[0] = UInt8(bitPattern: 1)
        bytes[1] = UInt8(bitPattern: 2)
        bytes[2] = UInt8(bitPattern: 3)
        bytes[3] = UInt8(bitPattern: -1)
        bytes[4] = UInt8(bitPattern: -2)
        bytes[5] = UInt8(bitPattern: -3)
        let field = ESMFixture.field("VNML", Data(bytes))
        let land = try Land(record: record(ESMFixture.record("LAND", data: field)))
        let normals = try #require(land.normals)
        #expect(normals.count == Land.vertexCount)
        #expect(normals[0] == SIMD3<Int8>(1, 2, 3))
        #expect(normals[1] == SIMD3<Int8>(-1, -2, -3))
        #expect(land.colors == nil) // VCLR optional
    }

    @Test func decodesVCLR() throws {
        var bytes = [UInt8](repeating: 0, count: Land.vertexCount * 3)
        bytes[0] = 255
        bytes[1] = 128
        bytes[2] = 0
        let field = ESMFixture.field("VCLR", Data(bytes))
        let land = try Land(record: record(ESMFixture.record("LAND", data: field)))
        let colors = try #require(land.colors)
        #expect(colors.count == Land.vertexCount)
        #expect(colors[0] == SIMD3<UInt8>(255, 128, 0))
    }

    // MARK: - LAND texture layers

    @Test func decodesBTXTAndATXTVTXTPairing() throws {
        let fields = ESMFixture.field("BTXT", textureHeader(texture: 0x1234, quadrant: 2, layer: 0))
            + ESMFixture.field("ATXT", textureHeader(texture: 0x5678, quadrant: 1, layer: 1))
            + ESMFixture.field(
                "VTXT",
                vtxt([(position: 0, opacity: 1.0), (position: 288, opacity: 0.5)])
            )
            + ESMFixture.field("ATXT", textureHeader(texture: 0x9ABC, quadrant: 3, layer: 2))
            + ESMFixture.field("VTXT", vtxt([(position: 144, opacity: 0.25)]))
        let land = try Land(record: record(ESMFixture.record("LAND", data: fields)))

        #expect(land.baseTextures == [
            Land.QuadrantTexture(texture: FormID(0x1234), quadrant: 2, layer: 0)
        ])
        // Two layers, preserved in on-disk order (blend order matters).
        #expect(land.layers.count == 2)
        #expect(land.layers[0].texture == FormID(0x5678))
        #expect(land.layers[0].quadrant == 1)
        #expect(land.layers[0].layer == 1)
        #expect(land.layers[0].alphas == [
            Land.AlphaSample(position: 0, opacity: 1.0),
            Land.AlphaSample(position: 288, opacity: 0.5)
        ])
        #expect(land.layers[1].texture == FormID(0x9ABC))
        #expect(land.layers[1].layer == 2)
        #expect(land.layers[1].alphas == [Land.AlphaSample(position: 144, opacity: 0.25)])
        // Quadrant + position stay within documented bounds.
        for layer in land.layers {
            #expect((0 ... 3).contains(layer.quadrant))
            for alpha in layer.alphas {
                #expect(alpha.position <= 288)
            }
        }
    }

    // MARK: - Compressed round-trip

    @Test func decodesCompressedLAND() throws {
        // Real LAND records are zlib-compressed (flag bit 18); fields() must
        // decompress transparently before the subrecords parse.
        var data = Data()
        data.appendUInt32(0x2A)
        let fields = ESMFixture.field("DATA", data)
            + ESMFixture.field("VHGT", vhgt(anchor: 0, deltas: [Delta(row: 0, col: 0, value: 1)]))
            + ESMFixture.field("BTXT", textureHeader(texture: 0xABCD, quadrant: 0, layer: 0))
        let land = try Land(
            record: record(ESMFixture.compressedRecord("LAND", formID: 0x77, fieldData: fields))
        )
        #expect(land.formID == FormID(0x77))
        #expect(land.flags == 0x2A)
        #expect(land.heightField?.heights[0] == 8) // (0 + 1) * 8
        #expect(land.baseTextures.first?.texture == FormID(0xABCD))
    }

    // MARK: - Rejections

    @Test func landRejectsWrongRecordType() {
        let statBytes = ESMFixture.record("STAT", data: Data())
        #expect(throws: (any Error).self) {
            _ = try Land(record: record(statBytes))
        }
    }

    @Test func landRejectsMalformedSizes() {
        let shortVHGT = ESMFixture.record("LAND", data: ESMFixture.field("VHGT", Data(count: 100)))
        #expect(throws: (any Error).self) {
            _ = try Land(record: record(shortVHGT))
        }
        let shortVNML = ESMFixture.record("LAND", data: ESMFixture.field("VNML", Data(count: 10)))
        #expect(throws: (any Error).self) {
            _ = try Land(record: record(shortVNML))
        }
        // VTXT not a whole number of 8-byte entries.
        let badVTXT = ESMFixture.record(
            "LAND",
            data:
            ESMFixture.field("ATXT", textureHeader(texture: 1, quadrant: 0, layer: 1))
                + ESMFixture.field("VTXT", Data(count: 12))
        )
        #expect(throws: (any Error).self) {
            _ = try Land(record: record(badVTXT))
        }
    }

    // MARK: - LTEX

    @Test func decodesLandTexture() throws {
        var tnam = Data()
        tnam.appendUInt32(0x0001_0A5C)
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("LandscapeDirt01"))
            + ESMFixture.field("TNAM", tnam)
            + ESMFixture.field("MNAM", Data(count: 4)) // skipped
        let ltex = try LandTexture(
            record: record(ESMFixture.record("LTEX", formID: 0x5A, data: fields))
        )
        #expect(ltex.formID == FormID(0x5A))
        #expect(ltex.editorID == "LandscapeDirt01")
        #expect(ltex.textureSet == FormID(0x0001_0A5C))
    }

    @Test func landTextureRejectsWrongRecordType() {
        #expect(throws: (any Error).self) {
            _ = try LandTexture(record: record(ESMFixture.record("STAT", data: Data())))
        }
    }

    // MARK: - TXST

    @Test func decodesTextureSet() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("LDirt01"))
            + ESMFixture.field("TX00", ESMFixture.zstring("Textures\\Landscape\\Dirt01.dds"))
            + ESMFixture.field("TX01", ESMFixture.zstring("Textures\\Landscape\\Dirt01_n.dds"))
            + ESMFixture.field("TX02", ESMFixture.zstring("skipped.dds"))
            + ESMFixture.field("DNAM", Data(count: 4)) // skipped
        let txst = try TextureSet(
            record: record(ESMFixture.record("TXST", formID: 0x6B, data: fields))
        )
        #expect(txst.formID == FormID(0x6B))
        #expect(txst.editorID == "LDirt01")
        #expect(txst.diffusePath == "Textures\\Landscape\\Dirt01.dds")
        #expect(txst.normalPath == "Textures\\Landscape\\Dirt01_n.dds")
    }

    @Test func textureSetRejectsWrongRecordType() {
        #expect(throws: (any Error).self) {
            _ = try TextureSet(record: record(ESMFixture.record("LTEX", data: Data())))
        }
    }
}
