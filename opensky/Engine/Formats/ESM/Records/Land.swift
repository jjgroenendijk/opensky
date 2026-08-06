// LAND record decoded into engine terrain types: per-vertex height field,
// normals, optional vertex colors, and the per-quadrant texture layer stack.
// LAND lives in a cell's temporary-children group (type 9) and is almost
// always zlib-compressed (record flag bit 18) — ESMRecord.fields() decompresses
// transparently, so this decoder just reads subrecords.
//
// Reference: UESP "Skyrim Mod:Mod File Format/LAND"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/LAND
// Cross-checked against xEdit dev-4.1.6 wbDefinitionsCommon.pas (wbLAND).
// Layout + VHGT accumulation math documented in docs/formats/land.md.

import Foundation
import simd

nonisolated struct Land {
    /// One cell edge is a 33x33 vertex grid (32 quads at 128 game units each,
    /// spanning the 4096-unit cell). Rows run south->north, columns west->east.
    static let dimension = 33
    /// 33x33 vertices per subrecord grid.
    static let vertexCount = dimension * dimension

    /// VHGT: gradient-coded height map. Stored as a float anchor plus signed
    /// per-vertex deltas; `heights` is the fully accumulated, *8-scaled field.
    struct HeightField {
        /// Raw VHGT offset float — accumulation seed, before the *8 scale.
        let anchor: Float
        /// 1089 heights in game units, row-major south->north / west->east.
        let heights: [Float]
    }

    /// BTXT: the base texture covering one quadrant (layer 0 of the splat).
    struct QuadrantTexture: Equatable {
        /// LTEX FormID this quadrant's base texture resolves to.
        let texture: FormID
        /// Quadrant index 0-3 (bottom-left, bottom-right, top-left, top-right).
        let quadrant: UInt8
        /// Layer number — 0/-1 for the base per spec, kept verbatim.
        let layer: Int16
    }

    /// One VTXT entry: an alpha weight for an additional layer at a vertex on
    /// the quadrant's 17x17 sub-grid.
    struct AlphaSample: Equatable {
        /// Vertex index 0-288 on the 17x17 quadrant grid.
        let position: UInt16
        /// Blend weight 0.0-1.0.
        let opacity: Float
    }

    /// ATXT header plus the VTXT alpha map that follows it. Order in `layers`
    /// is the on-disk order — the layer number drives splat blend order.
    struct TextureLayer {
        /// LTEX FormID this layer's texture resolves to.
        let texture: FormID
        /// Quadrant index 0-3.
        let quadrant: UInt8
        /// Layer number (blend order above the base).
        let layer: Int16
        /// Sparse per-vertex alpha weights from the paired VTXT.
        let alphas: [AlphaSample]
    }

    let formID: FormID
    /// DATA — land flags (quadrant include bits etc.); kept raw for now.
    let flags: UInt32
    /// VHGT height field. Nil only for a degenerate LAND without heights.
    let heightField: HeightField?
    /// VNML — 33x33 signed per-vertex normals (x, y, z). Nil when absent.
    let normals: [SIMD3<Int8>]?
    /// VCLR — 33x33 per-vertex colors (r, g, b). Optional subrecord.
    let colors: [SIMD3<UInt8>]?
    /// BTXT base textures, one per painted quadrant.
    let baseTextures: [QuadrantTexture]
    /// ATXT/VTXT additional layers in on-disk order.
    let layers: [TextureLayer]

    init(record: ESMRecord) throws {
        guard record.type == "LAND" else {
            throw ESMError.malformed("expected LAND record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var flags: UInt32 = 0
        var heightField: HeightField?
        var normals: [SIMD3<Int8>]?
        var colors: [SIMD3<UInt8>]?
        var baseTextures: [QuadrantTexture] = []
        var layers: [TextureLayer] = []
        // ATXT header awaiting its VTXT alpha map (subrecords arrive paired).
        var pendingLayer: QuadrantTexture?

        func flushPendingLayer(alphas: [AlphaSample]) {
            guard let pending = pendingLayer else { return }
            layers.append(TextureLayer(
                texture: pending.texture,
                quadrant: pending.quadrant,
                layer: pending.layer,
                alphas: alphas
            ))
            pendingLayer = nil
        }

        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "DATA":
                flags = try reader.readUInt32()
            case "VHGT":
                heightField = try Self.decodeHeightField(field.data)
            case "VNML":
                normals = try Self.decodeInt8Triples(field.data, name: "VNML")
            case "VCLR":
                colors = try Self.decodeUInt8Triples(field.data, name: "VCLR")
            case "BTXT":
                try baseTextures.append(Self.decodeQuadrantTexture(&reader))
            case "ATXT":
                // A dangling ATXT (no VTXT) still records the layer, empty.
                flushPendingLayer(alphas: [])
                pendingLayer = try Self.decodeQuadrantTexture(&reader)
            case "VTXT":
                let alphas = try Self.decodeAlphaSamples(field.data)
                // VTXT with no preceding ATXT is malformed — dropped, not fatal.
                flushPendingLayer(alphas: alphas)
            default:
                break
            }
        }
        flushPendingLayer(alphas: [])

        self.flags = flags
        self.heightField = heightField
        self.normals = normals
        self.colors = colors
        self.baseTextures = baseTextures
        self.layers = layers
    }

    /// VHGT: 4-byte anchor float, 33x33 int8 deltas, 3 unused bytes (1096 B).
    /// Heights are gradient-coded: column 0 of each row is a delta from the
    /// previous row's column-0 value (row 0 from the anchor), columns 1-32
    /// accumulate west->east from their row's column 0. Final game-unit height
    /// = accumulated value * 8. Ref UESP LAND + xEdit wbLAND VHGT decode.
    private static func decodeHeightField(_ data: Data) throws -> HeightField {
        let expected = 4 + vertexCount + 3
        guard data.count == expected else {
            throw ESMError.malformed("VHGT size \(data.count), expected \(expected)")
        }
        var reader = BinaryReader(data)
        let anchor = try reader.readFloat32()
        var deltas = [Int8](repeating: 0, count: vertexCount)
        for index in 0 ..< vertexCount {
            deltas[index] = try Int8(bitPattern: reader.readUInt8())
        }
        var heights = [Float](repeating: 0, count: vertexCount)
        var columnZero = anchor
        for row in 0 ..< dimension {
            columnZero += Float(deltas[row * dimension])
            var running = columnZero
            heights[row * dimension] = running * 8
            for column in 1 ..< dimension {
                running += Float(deltas[row * dimension + column])
                heights[row * dimension + column] = running * 8
            }
        }
        return HeightField(anchor: anchor, heights: heights)
    }

    /// VNML: 33x33x3 signed bytes (3267 B).
    private static func decodeInt8Triples(_ data: Data, name: String) throws -> [SIMD3<Int8>] {
        let expected = vertexCount * 3
        guard data.count == expected else {
            throw ESMError.malformed("\(name) size \(data.count), expected \(expected)")
        }
        var reader = BinaryReader(data)
        var out = [SIMD3<Int8>]()
        out.reserveCapacity(vertexCount)
        for _ in 0 ..< vertexCount {
            let x = try Int8(bitPattern: reader.readUInt8())
            let y = try Int8(bitPattern: reader.readUInt8())
            let z = try Int8(bitPattern: reader.readUInt8())
            out.append(SIMD3(x, y, z))
        }
        return out
    }

    /// VCLR: 33x33x3 unsigned bytes (3267 B).
    private static func decodeUInt8Triples(_ data: Data, name: String) throws -> [SIMD3<UInt8>] {
        let expected = vertexCount * 3
        guard data.count == expected else {
            throw ESMError.malformed("\(name) size \(data.count), expected \(expected)")
        }
        var reader = BinaryReader(data)
        var out = [SIMD3<UInt8>]()
        out.reserveCapacity(vertexCount)
        for _ in 0 ..< vertexCount {
            let r = try reader.readUInt8()
            let g = try reader.readUInt8()
            let b = try reader.readUInt8()
            out.append(SIMD3(r, g, b))
        }
        return out
    }

    /// BTXT/ATXT header: uint32 LTEX FormID, uint8 quadrant, uint8 unused,
    /// int16 layer (8 B).
    private static func decodeQuadrantTexture(
        _ reader: inout BinaryReader
    ) throws -> QuadrantTexture {
        let texture = try FormID(reader.readUInt32())
        let quadrant = try reader.readUInt8()
        _ = try reader.readUInt8() // unused
        let layer = try Int16(bitPattern: reader.readUInt16())
        return QuadrantTexture(texture: texture, quadrant: quadrant, layer: layer)
    }

    /// VTXT: array of 8-byte entries — uint16 position, uint16 unused, float32
    /// opacity. Size must be a whole number of entries.
    private static func decodeAlphaSamples(_ data: Data) throws -> [AlphaSample] {
        guard data.count % 8 == 0 else {
            throw ESMError.malformed("VTXT size \(data.count) not a multiple of 8")
        }
        var reader = BinaryReader(data)
        var out = [AlphaSample]()
        out.reserveCapacity(data.count / 8)
        for _ in 0 ..< (data.count / 8) {
            let position = try reader.readUInt16()
            _ = try reader.readUInt16() // two unused bytes
            let opacity = try reader.readFloat32()
            out.append(AlphaSample(position: position, opacity: opacity))
        }
        return out
    }
}
