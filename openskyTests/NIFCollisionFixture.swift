// Synthetic bhk payload builders. Layouts follow NifTools nif.xml; no game
// bytes or extracted assets are fixtures (AGENTS.md legal boundary).

import Foundation
import simd

enum NIFCollisionFixture {
    static func collisionObject(
        target: Int32 = 0,
        flags: UInt16 = 0x81,
        body: Int32
    ) -> Data {
        var data = Data()
        data.appendRef(target)
        data.appendUInt16(flags)
        data.appendRef(body)
        return data
    }

    static func rigidBody(
        shape: Int32,
        worldLayer: UInt8 = 1,
        worldFlags: UInt8 = 0,
        rigidLayer: UInt8 = 1,
        rigidFlags: UInt8 = 0,
        entityResponse: UInt8 = 1,
        rigidResponse: UInt8 = 1,
        translation: SIMD3<Float> = .zero,
        rotation: SIMD4<Float> = SIMD4(0, 0, 0, 1),
        motionSystem: UInt8 = 7
    ) -> Data {
        var data = Data()
        data.appendRef(shape)
        data.appendFilter(layer: worldLayer, flags: worldFlags)
        data.append(Data(count: 20)) // bhkWorldObjectCInfo
        data.append(entityResponse)
        data.append(0)
        data.appendUInt16(0xFFFF)

        data.append(Data(count: 4))
        data.appendFilter(layer: rigidLayer, flags: rigidFlags)
        data.append(Data(count: 8))
        data.append(rigidResponse)
        data.append(0)
        data.appendUInt16(0xFFFF)
        data.appendVector4(SIMD4(translation, 0))
        data.appendVector4(rotation)
        data.append(Data(count: 96)) // velocities, inertia, center
        for _ in 0 ..< 11 {
            data.appendFloat32(0)
        }
        data.append(motionSystem)
        data.append(contentsOf: [1, 1, 1]) // deactivator, solver, quality
        data.append(contentsOf: [0, 0, 3, 0])
        data.append(Data(count: 12))
        data.appendUInt32(0) // constraints
        data.appendUInt16(0) // body flags: BS stream >= 76
        return data
    }

    static func list(_ refs: [Int32]) -> Data {
        var data = Data()
        data.appendUInt32(UInt32(refs.count))
        refs.forEach { data.appendRef($0) }
        return data
    }

    static func sphere(radius: Float) -> Data {
        var data = Data()
        data.appendUInt32(0)
        data.appendFloat32(radius)
        return data
    }

    static func box(_ halfExtents: SIMD3<Float>) -> Data {
        var data = Data()
        data.appendUInt32(0)
        data.appendFloat32(0.05)
        data.append(Data(count: 8))
        data.appendVector3(halfExtents)
        data.appendFloat32(0)
        return data
    }

    static func capsule(
        first: SIMD3<Float>,
        second: SIMD3<Float>,
        radius: Float
    ) -> Data {
        var data = Data()
        data.appendUInt32(0)
        data.appendFloat32(0.05)
        data.append(Data(count: 8))
        data.appendVector3(first)
        data.appendFloat32(radius)
        data.appendVector3(second)
        data.appendFloat32(radius)
        return data
    }

    static func convexVertices(_ vertices: [SIMD3<Float>]) -> Data {
        var data = Data()
        data.appendUInt32(0)
        data.appendFloat32(0.05)
        data.append(Data(count: 24))
        data.appendUInt32(UInt32(vertices.count))
        vertices.forEach { data.appendVector4(SIMD4($0, 0)) }
        data.appendUInt32(0) // normals
        return data
    }

    static func transformShape(child: Int32, translation: SIMD3<Float>) -> Data {
        var data = Data()
        data.appendRef(child)
        data.appendUInt32(0)
        data.appendFloat32(0.05)
        data.append(Data(count: 8))
        data.appendMatrix(translation: translation)
        return data
    }

    static func mopp(child: Int32) -> Data {
        var data = Data()
        data.appendRef(child)
        return data
    }

    static func compressedShape(
        dataRef: Int32,
        scale: SIMD3<Float> = SIMD3(repeating: 1)
    ) -> Data {
        var data = Data(count: 16)
        data.appendVector4(SIMD4(scale, 0))
        data.appendFloat32(0.005)
        data.appendVector4(SIMD4(scale, 0))
        data.appendRef(dataRef)
        return data
    }

    static func compressedData() -> Data {
        var data = Data()
        data.appendUInt32(17)
        data.appendUInt32(18)
        data.appendUInt32(0x3FFFF)
        data.appendUInt32(0x1FFFF)
        data.appendFloat32(0.001)
        data.appendVector4(.zero)
        data.appendVector4(SIMD4(repeating: 10))
        data.append(contentsOf: [0, 1])
        data.appendUInt32(0)
        data.appendUInt32(0)
        data.appendUInt32(0)
        data.appendUInt32(1)
        data.appendUInt32(0)
        data.appendFilter(layer: 1)
        data.appendUInt32(0) // named materials
        data.appendUInt32(0) // transforms

        let bigVertices = [
            SIMD4<Float>(0, 0, 0, 0),
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0)
        ]
        data.appendUInt32(UInt32(bigVertices.count))
        bigVertices.forEach { data.appendVector4($0) }
        data.appendUInt32(1)
        data.appendUInt16(0)
        data.appendUInt16(1)
        data.appendUInt16(2)
        data.appendUInt32(0)
        data.appendUInt16(0)

        data.appendUInt32(1) // chunks
        data.appendVector4(SIMD4<Float>(1, 2, 3, 0))
        data.appendUInt32(0)
        data.appendUInt16(.max)
        data.appendUInt16(.max)
        let vertices: [SIMD3<UInt16>] = [
            SIMD3(0, 0, 0),
            SIMD3(1000, 0, 0),
            SIMD3(1000, 1000, 0),
            SIMD3(0, 1000, 0)
        ]
        data.appendUInt32(UInt32(vertices.count * 3))
        for vertex in vertices {
            data.appendUInt16(vertex.x)
            data.appendUInt16(vertex.y)
            data.appendUInt16(vertex.z)
        }
        let indices: [UInt16] = [0, 1, 2, 3, 0, 2, 3]
        data.appendUInt32(UInt32(indices.count))
        indices.forEach { data.appendUInt16($0) }
        data.appendUInt32(1)
        data.appendUInt16(4)
        data.appendUInt32(UInt32(indices.count))
        indices.forEach { _ in data.appendUInt16(0) }
        data.appendUInt32(0) // convex pieces
        return data
    }

    static func packedShape(dataRef: Int32) -> Data {
        var data = Data(count: 16)
        data.appendVector4(SIMD4<Float>(1, 1, 1, 0))
        data.appendFloat32(0.1)
        data.appendVector4(SIMD4<Float>(1, 1, 1, 0))
        data.appendRef(dataRef)
        return data
    }

    static func packedData() -> Data {
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
        data.appendUInt32(0)
        return data
    }

    static func niTriStripsShape(dataRef: Int32) -> Data {
        var data = Data()
        data.appendUInt32(0)
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

extension Data {
    fileprivate mutating func appendRef(_ value: Int32) {
        appendUInt32(UInt32(bitPattern: value))
    }

    fileprivate mutating func appendFilter(layer: UInt8, flags: UInt8 = 0, group: UInt16 = 0) {
        append(layer)
        append(flags)
        appendUInt16(group)
    }

    fileprivate mutating func appendVector3(_ value: SIMD3<Float>) {
        appendFloat32(value.x)
        appendFloat32(value.y)
        appendFloat32(value.z)
    }

    fileprivate mutating func appendVector4(_ value: SIMD4<Float>) {
        appendFloat32(value.x)
        appendFloat32(value.y)
        appendFloat32(value.z)
        appendFloat32(value.w)
    }

    fileprivate mutating func appendMatrix(translation: SIMD3<Float>) {
        appendVector4(SIMD4(1, 0, 0, 0))
        appendVector4(SIMD4(0, 1, 0, 0))
        appendVector4(SIMD4(0, 0, 1, 0))
        appendVector4(SIMD4(translation, 1))
    }
}
