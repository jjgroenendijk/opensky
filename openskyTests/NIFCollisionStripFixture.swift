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
        data.appendUInt32(0)
        data.appendRef(-1)
        data.appendUInt16(2)
        data.appendUInt16(1)
        data.appendUInt16(4)
        data.append(1)
        [UInt16(0), 1, 2, 3].forEach { data.appendUInt16($0) }
        return data
    }
}
