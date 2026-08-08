// Synthetic bhk payload builders. Layouts follow NifTools nif.xml; no game
// bytes or extracted assets are fixtures (AGENTS.md legal boundary).

import Foundation
import simd

enum NIFCollisionFixture {
    /// The inertial tail of `bhkRigidBodyCInfo2010`, so a test names only the
    /// fields it cares about. Values are in the file's own units: metres,
    /// kilograms, radians.
    struct Dynamics {
        var linearVelocity: SIMD3<Float> = .zero
        var angularVelocity: SIMD3<Float> = .zero
        /// Rows in nif.xml order: m11 m12 m13 | m21 m22 m23 | m31 m32 m33.
        var inertiaRows: [SIMD3<Float>] = [
            SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)
        ]
        var center: SIMD3<Float> = .zero
        var mass: Float = 0
        var linearDamping: Float = 0
        var angularDamping: Float = 0
        var timeFactor: Float = 1
        var gravityFactor: Float = 1
        var friction: Float = 0
        var rollingFrictionMultiplier: Float = 0
        var restitution: Float = 0
        var maxLinearVelocity: Float = 0
        var maxAngularVelocity: Float = 0
        var penetrationDepth: Float = 0
        var deactivatorType: UInt8 = 1
        var solverDeactivation: UInt8 = 1
        var qualityType: UInt8 = 1
    }

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

    /// `bhkBlendCollisionObject` inherits `bhkCollisionObject` and appends two
    /// blend-gain floats (nif.xml).
    static func blendCollisionObject(
        target: Int32 = 0,
        flags: UInt16 = 0x89,
        body: Int32
    ) -> Data {
        var data = collisionObject(target: target, flags: flags, body: body)
        data.appendFloat32(1)
        data.appendFloat32(1)
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
        motionSystem: UInt8 = 7,
        dynamics: Dynamics = Dynamics(),
        constraints: [Int32] = [],
        constraintCountOverride: UInt32? = nil,
        bodyFlags: UInt16 = 0
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
        data.append(inertialTail(dynamics, motionSystem: motionSystem))
        data.append(contentsOf: [0, 0, 3, 0])
        data.append(Data(count: 12))
        data.appendUInt32(constraintCountOverride ?? UInt32(constraints.count))
        constraints.forEach { data.appendRef($0) }
        data.appendUInt16(bodyFlags) // BS stream >= 76 stores this as a ushort
        return data
    }

    private static func inertialTail(
        _ dynamics: Dynamics,
        motionSystem: UInt8
    ) -> Data {
        var data = Data()
        data.appendVector4(SIMD4(dynamics.linearVelocity, 0))
        data.appendVector4(SIMD4(dynamics.angularVelocity, 0))
        for row in dynamics.inertiaRows {
            data.appendVector4(SIMD4(row, 0))
        }
        data.appendVector4(SIMD4(dynamics.center, 0))
        for value in [
            dynamics.mass, dynamics.linearDamping, dynamics.angularDamping,
            dynamics.timeFactor, dynamics.gravityFactor, dynamics.friction,
            dynamics.rollingFrictionMultiplier, dynamics.restitution,
            dynamics.maxLinearVelocity, dynamics.maxAngularVelocity,
            dynamics.penetrationDepth
        ] {
            data.appendFloat32(value)
        }
        data.append(motionSystem)
        data.append(dynamics.deactivatorType)
        data.append(dynamics.solverDeactivation)
        data.append(dynamics.qualityType)
        return data
    }

    static func list(_ refs: [Int32]) -> Data {
        var data = Data()
        data.appendUInt32(UInt32(refs.count))
        refs.forEach { data.appendRef($0) }
        return data
    }

    static func sphere(radius: Float, material: UInt32 = 0) -> Data {
        var data = Data()
        data.appendUInt32(material)
        data.appendFloat32(radius)
        return data
    }

    static func box(_ halfExtents: SIMD3<Float>, material: UInt32 = 0) -> Data {
        var data = Data()
        data.appendUInt32(material)
        data.appendFloat32(0.05)
        data.append(Data(count: 8))
        data.appendVector3(halfExtents)
        data.appendFloat32(0)
        return data
    }

    static func capsule(
        first: SIMD3<Float>,
        second: SIMD3<Float>,
        radius: Float,
        material: UInt32 = 0
    ) -> Data {
        var data = Data()
        data.appendUInt32(material)
        data.appendFloat32(0.05)
        data.append(Data(count: 8))
        data.appendVector3(first)
        data.appendFloat32(radius)
        data.appendVector3(second)
        data.appendFloat32(radius)
        return data
    }

    static func convexVertices(
        _ vertices: [SIMD3<Float>],
        normals: [SIMD4<Float>] = [],
        material: UInt32 = 0
    ) -> Data {
        var data = Data()
        data.appendUInt32(material)
        data.appendFloat32(0.05)
        data.append(Data(count: 24))
        data.appendUInt32(UInt32(vertices.count))
        vertices.forEach { data.appendVector4(SIMD4($0, 0)) }
        data.appendUInt32(UInt32(normals.count))
        normals.forEach { data.appendVector4($0) }
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

    static func compressedData(
        materials: [UInt32] = [0],
        bigTriangleMaterialIndex: UInt32 = 0,
        chunkMaterialIndex: UInt32 = 0
    ) -> Data {
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
        data.appendUInt32(UInt32(materials.count))
        for material in materials {
            data.appendUInt32(material)
            data.appendFilter(layer: 1)
        }
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
        data.appendUInt32(bigTriangleMaterialIndex)
        data.appendUInt16(0)

        data.appendUInt32(1) // chunks
        data.appendVector4(SIMD4<Float>(1, 2, 3, 0))
        data.appendUInt32(chunkMaterialIndex)
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
}

/// Internal rather than fileprivate: NIFCollisionStripFixture.swift builds the
/// packed-strips payloads with the same primitives.
extension Data {
    mutating func appendRef(_ value: Int32) {
        appendUInt32(UInt32(bitPattern: value))
    }

    mutating func appendFilter(layer: UInt8, flags: UInt8 = 0, group: UInt16 = 0) {
        append(layer)
        append(flags)
        appendUInt16(group)
    }

    mutating func appendVector3(_ value: SIMD3<Float>) {
        appendFloat32(value.x)
        appendFloat32(value.y)
        appendFloat32(value.z)
    }

    mutating func appendVector4(_ value: SIMD4<Float>) {
        appendFloat32(value.x)
        appendFloat32(value.y)
        appendFloat32(value.z)
        appendFloat32(value.w)
    }

    mutating func appendMatrix(translation: SIMD3<Float>) {
        appendVector4(SIMD4(1, 0, 0, 0))
        appendVector4(SIMD4(0, 1, 0, 0))
        appendVector4(SIMD4(0, 0, 1, 0))
        appendVector4(SIMD4(translation, 1))
    }
}
