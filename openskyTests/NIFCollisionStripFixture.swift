// The packed-strips and NiTriStrips halves of the synthetic bhk payload
// builders, split from NIFCollisionFixture.swift to keep each inside the
// strict type-body limit. Layouts follow NifTools nif.xml; no game bytes or
// extracted assets are fixtures (AGENTS.md legal boundary).

import Foundation
import simd

extension NIFCollisionFixture {
    static func packedShape(dataRef: Int32) -> Data {
        var data = Data(count: 16)
        data.appendVector4(SIMD4<Float>(1, 1, 1, 0))
        data.appendFloat32(0.1)
        data.appendVector4(SIMD4<Float>(1, 1, 1, 0))
        data.appendRef(dataRef)
        return data
    }

    static func packedData(material: UInt32 = 0) -> Data {
        var data = Data()
        data.appendUInt32(1)
        data.appendUInt16(0)
        data.appendUInt16(1)
        data.appendUInt16(2)
        data.appendUInt16(0)
        data.appendUInt32(3)
        data.append(0) // uncompressed
        data.appendVector3(SIMD3(0, 0, 0))
        data.appendVector3(SIMD3(1, 0, 0))
        data.appendVector3(SIMD3(0, 1, 0))
        data.appendUInt16(1)
        data.appendFilter(layer: 1)
        data.appendUInt32(3)
        data.appendUInt32(material)
        return data
    }

    static func niTriStripsShape(dataRef: Int32, material: UInt32 = 0) -> Data {
        var data = Data()
        data.appendUInt32(material)
        data.appendFloat32(0.1)
        data.append(Data(count: 20))
        data.appendUInt32(1)
        data.appendVector4(SIMD4<Float>(1, 1, 1, 0))
        data.appendUInt32(1)
        data.appendRef(dataRef)
        return data
    }

    static func niTriStripsData() -> Data {
        var data = Data()
        data.appendUInt32(0)
        data.appendUInt16(4)
        data.append(contentsOf: [0, 0, 1])
        data.appendVector3(SIMD3(0, 0, 0))
        data.appendVector3(SIMD3(1, 0, 0))
        data.appendVector3(SIMD3(1, 1, 0))
        data.appendVector3(SIMD3(0, 1, 0))
        data.appendUInt16(0)
        data.appendUInt32(0)
        data.append(0)
        data.appendVector4(.zero)
        data.append(0)
        data.appendUInt16(0) // Consistency Flags: a ushort, not a uint
        data.appendRef(-1)
        data.appendUInt16(2)
        data.appendUInt16(1)
        data.appendUInt16(4)
        data.append(1)
        [UInt16(0), 1, 2, 3].forEach { data.appendUInt16($0) }
        return data
    }

    /// The shape of the vanilla `bhkNiTriStripsShape` blocks: every optional
    /// `NiGeometryData` array present (normals with tangents, vertex colors,
    /// one UV set) and several strips of differing length. A field width that
    /// is wrong anywhere in the prefix walks the point array off its vertices
    /// or misreads the strip table, which is what issue #376 was.
    static func niTriStripsDataFullPrefix() -> Data {
        var data = Data()
        data.appendUInt32(0) // Group ID
        data.appendUInt16(6) // Num Vertices
        data.append(contentsOf: [0, 0, 1]) // keep flags, compress flags, has vertices
        let vertices: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0),
            SIMD3(0, 1, 0), SIMD3(0, 0, 1), SIMD3(1, 0, 1)
        ]
        vertices.forEach { data.appendVector3($0) }
        data.appendUInt16(0x1001) // BS Vector Flags: has UV + has tangents
        data.appendUInt32(0xDEAD_BEEF) // Material CRC (a render material; skipped)
        data.append(1) // has normals
        data.append(Data(count: vertices.count * 12)) // normals
        data.append(Data(count: vertices.count * 24)) // tangents + bitangents
        data.appendVector4(.zero) // NiBound
        data.append(1) // has vertex colors
        data.append(Data(count: vertices.count * 16)) // colors
        data.append(Data(count: vertices.count * 8)) // one UV set
        data.appendUInt16(0x4000) // Consistency Flags
        data.appendRef(-1) // Additional Data
        data.appendUInt16(4) // Num Triangles: 2 from the quad strip, 1 each from the pair
        data.appendUInt16(3) // Num Strips
        [UInt16(4), 3, 3].forEach { data.appendUInt16($0) }
        data.append(1) // has points
        [UInt16(0), 1, 2, 3, 1, 2, 4, 2, 4, 5].forEach { data.appendUInt16($0) }
        return data
    }
}
