// bhkRigidBody / bhkRigidBodyT block layout for Skyrim SE streams, read whole
// rather than skipped: the query path needs the filters and responses, and a
// dynamic simulation needs the inertial tail behind them.
//
// Field order, in the order read below (nif.xml):
//   bhkWorldObject   shape ref (4), HavokFilter (4), bhkWorldObjectCInfo (20)
//   bhkEntity        bhkEntityCInfo: response (1), unused (1), delay (2)
//   bhkRigidBodyCInfo2010
//                    unused (4), HavokFilter (4), unused (4), unknown (4),
//                    response (1), unused (1), delay (2),
//                    translation (16), rotation (16),
//                    linear velocity (16), angular velocity (16),
//                    inertia tensor (48), center (16),
//                    mass, linear damping, angular damping, time factor,
//                    gravity factor, friction, rolling friction multiplier,
//                    restitution, max linear velocity, max angular velocity,
//                    penetration depth (4 each),
//                    motion system, deactivator, solver deactivation,
//                    quality, auto remove level, response modifier flags,
//                    shape keys in contact point, force collided onto PPU
//                    (1 each), unused (12)
//   bhkRigidBody     constraint count (4), constraint refs (4 each),
//                    body flags (2 for BS stream >= 76)
//
// Reference: NifTools nif.xml (bhkWorldObject, bhkEntity, bhkRigidBody,
// bhkRigidBodyCInfo2010). The 550_660 and 2014 CInfo variants belong to
// pre-Skyrim and Fallout 4 streams and are not read.
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
// Layout documented in docs/formats/nif-collision.md.

import Foundation
import simd

/// Everything one rigid-body block holds, before scene transforms compose in.
nonisolated struct NIFRigidBodyRecord {
    static let bodyTypeNames: Set = ["bhkRigidBody", "bhkRigidBodyT"]
    /// Refs are 4 bytes each and the body flags follow, so a count past this
    /// share of the remaining block cannot be real.
    static let maxConstraintCount = 256

    let shapeRef: Int32
    let worldFilter: NIFCollisionFilter
    let rigidBodyFilter: NIFCollisionFilter
    /// nif.xml `hkResponseType` from `bhkEntityCInfo`.
    let entityResponse: UInt8
    /// The same enum repeated inside `bhkRigidBodyCInfo2010`.
    let rigidBodyResponse: UInt8
    /// The body's own translation + rotation. Applied only by `bhkRigidBodyT`;
    /// a plain `bhkRigidBody` serializes it and ignores it.
    let localTransform: float4x4
    let dynamics: NIFRigidBodyDynamics
    /// Block refs to `bhkConstraint` subclasses, unresolved.
    let constraintRefs: [Int32]
    /// Bit 1 means the body responds to wind.
    let bodyFlags: UInt16

    init(data: Data) throws {
        var reader = BinaryReader(data)
        shapeRef = try reader.readNIFRef()
        worldFilter = try reader.readCollisionFilter()
        reader.skip(20) // bhkWorldObjectCInfo
        entityResponse = try reader.readUInt8()
        reader.skip(3) // unused byte + contact callback delay

        // Skyrim bhkRigidBodyCInfo2010. Keep both serialized filters and
        // responses: either can make a body query-only.
        reader.skip(4)
        rigidBodyFilter = try reader.readCollisionFilter()
        reader.skip(8) // padding + unknown uint
        rigidBodyResponse = try reader.readUInt8()
        reader.skip(3)
        localTransform = try reader.readHavokTransform()
        dynamics = try Self.readDynamics(&reader)
        constraintRefs = try Self.readConstraintRefs(&reader)
        bodyFlags = try reader.readUInt16()
    }

    private static func readDynamics(
        _ reader: inout BinaryReader
    ) throws -> NIFRigidBodyDynamics {
        let linearVelocity = try reader.readHavokAxis()
        let angularVelocity = try reader.readHavokAxis()
        let inertiaTensor = try reader.readHavokMatrix3()
        let centerOfMass = try reader.readHavokPoint()
        let scalars = try readScalars(&reader)
        return try NIFRigidBodyDynamics(
            mass: scalars.mass,
            inertiaTensor: inertiaTensor,
            centerOfMass: centerOfMass,
            linearVelocity: linearVelocity,
            angularVelocity: angularVelocity,
            linearDamping: scalars.linearDamping,
            angularDamping: scalars.angularDamping,
            timeFactor: scalars.timeFactor,
            gravityFactor: scalars.gravityFactor,
            friction: scalars.friction,
            rollingFrictionMultiplier: scalars.rollingFrictionMultiplier,
            restitution: scalars.restitution,
            maxLinearVelocity: scalars.maxLinearVelocity,
            maxAngularVelocity: scalars.maxAngularVelocity,
            penetrationDepth: scalars.penetrationDepth,
            rawMotionSystem: reader.readUInt8(),
            rawDeactivatorType: reader.readUInt8(),
            rawSolverDeactivation: reader.readUInt8(),
            rawQualityType: reader.readUInt8()
        )
    }

    /// The eleven-float run between the center of mass and the motion bytes,
    /// split out so `readDynamics` stays inside the function-length limit.
    private struct Scalars {
        let mass: Float
        let linearDamping: Float
        let angularDamping: Float
        let timeFactor: Float
        let gravityFactor: Float
        let friction: Float
        let rollingFrictionMultiplier: Float
        let restitution: Float
        let maxLinearVelocity: Float
        let maxAngularVelocity: Float
        let penetrationDepth: Float
    }

    private static func readScalars(_ reader: inout BinaryReader) throws -> Scalars {
        try Scalars(
            mass: reader.readFloat32(),
            linearDamping: reader.readFloat32(),
            angularDamping: reader.readFloat32(),
            timeFactor: reader.readFloat32(),
            gravityFactor: reader.readFloat32(),
            friction: reader.readFloat32(),
            rollingFrictionMultiplier: reader.readFloat32(),
            restitution: reader.readFloat32(),
            maxLinearVelocity: reader.readFloat32(),
            maxAngularVelocity: reader.readFloat32(),
            penetrationDepth: reader.readFloat32()
        )
    }

    private static func readConstraintRefs(
        _ reader: inout BinaryReader
    ) throws -> [Int32] {
        reader.skip(4) // auto remove level, response modifier flags,
        // shape keys in contact point, force collided onto PPU
        reader.skip(12) // unused tail of bhkRigidBodyCInfo2010
        let count = try Int(reader.readUInt32())
        guard count <= maxConstraintCount, count * 4 <= reader.bytesRemaining else {
            throw NIFError.malformed("rigid body constraint count \(count) exceeds block size")
        }
        var refs: [Int32] = []
        refs.reserveCapacity(count)
        for _ in 0 ..< count {
            try refs.append(reader.readNIFRef())
        }
        return refs
    }
}
