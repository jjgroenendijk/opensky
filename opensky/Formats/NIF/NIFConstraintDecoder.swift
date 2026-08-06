// Decode bhkConstraint blocks referenced from a rigid body's constraint list.
// Field order below is the Fallout 3 and later branch of each CInfo struct,
// which is the branch every Skyrim SE stream (20.2.0.7, BS > 16) takes; the
// Oblivion-era orders in nif.xml are deliberately not implemented.
//
// Reference: NifTools nif.xml (bhkConstraintCInfo and the per-type CInfo
// structs; the vercond used is `!#NI_BS_LTE_16#` / `since="20.2.0.7"`).
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
// Layout documented in docs/formats/nif-collision.md.

import Foundation
import simd

nonisolated enum NIFConstraintDecoder {
    /// Constraint block types this decoder reads, keyed to the `hkConstraintType`
    /// the block's payload follows.
    static let types: [String: NIFConstraintType] = [
        "bhkBallAndSocketConstraint": .ballAndSocket,
        "bhkHingeConstraint": .hinge,
        "bhkLimitedHingeConstraint": .limitedHinge,
        "bhkPrismaticConstraint": .prismatic,
        "bhkRagdollConstraint": .ragdoll,
        "bhkStiffSpringConstraint": .stiffSpring,
        "bhkMalleableConstraint": .malleable
    ]

    /// Throws `NIFError.unsupported` for a constraint class outside `types`,
    /// so the caller tallies it by block type and keeps the body.
    static func decode(block: NIFFile.Block, index: Int) throws -> NIFCollisionConstraint {
        guard let type = types[block.typeName] else {
            throw NIFError.unsupported("constraint class \(block.typeName)")
        }
        var reader = BinaryReader(block.data)
        let info = try readConstraintInfo(&reader)
        return try NIFCollisionConstraint(
            block: index,
            entityA: info.entityA,
            entityB: info.entityB,
            priority: info.priority,
            data: readData(type: type, reader: &reader)
        )
    }

    // MARK: - bhkConstraintCInfo

    private struct ConstraintInfo {
        let entityA: Int32
        let entityB: Int32
        let priority: UInt32
    }

    /// `Num Entities` is documented as hardcoded 2 and the two `Ptr` fields
    /// follow unconditionally, so the count is read and discarded rather than
    /// used as a length.
    private static func readConstraintInfo(
        _ reader: inout BinaryReader
    ) throws -> ConstraintInfo {
        reader.skip(4) // Num Entities, always 2
        return try ConstraintInfo(
            entityA: reader.readNIFRef(),
            entityB: reader.readNIFRef(),
            priority: reader.readUInt32()
        )
    }

    // MARK: - Per-type payloads

    private static func readData(
        type: NIFConstraintType,
        reader: inout BinaryReader
    ) throws -> NIFConstraintData {
        switch type {
        case .ballAndSocket:
            try .ballAndSocket(NIFBallAndSocketConstraint(
                pivotA: reader.readHavokPoint(),
                pivotB: reader.readHavokPoint()
            ))
        case .hinge:
            try .hinge(NIFHingeConstraint(
                frameA: readHingeFrame(&reader),
                frameB: readHingeFrame(&reader)
            ))
        case .limitedHinge:
            try .limitedHinge(readLimitedHinge(&reader))
        case .prismatic:
            try .prismatic(readPrismatic(&reader))
        case .ragdoll:
            try .ragdoll(readRagdoll(&reader))
        case .stiffSpring:
            try .stiffSpring(NIFStiffSpringConstraint(
                pivotA: reader.readHavokPoint(),
                pivotB: reader.readHavokPoint(),
                length: reader.readFloat32() * NIFCollisionModel.havokToEngineScale
            ))
        case .malleable:
            try readMalleable(&reader)
        }
    }

    private static func readHingeFrame(
        _ reader: inout BinaryReader
    ) throws -> NIFConstraintHingeFrame {
        try NIFConstraintHingeFrame(
            axis: reader.readHavokAxis(),
            perpAxis1: reader.readHavokAxis(),
            perpAxis2: reader.readHavokAxis(),
            pivot: reader.readHavokPoint()
        )
    }

    private static func readLimitedHinge(
        _ reader: inout BinaryReader
    ) throws -> NIFLimitedHingeConstraint {
        try NIFLimitedHingeConstraint(
            frameA: readHingeFrame(&reader),
            frameB: readHingeFrame(&reader),
            minAngle: reader.readFloat32(),
            maxAngle: reader.readFloat32(),
            maxFriction: reader.readFloat32(),
            motor: readMotor(&reader)
        )
    }

    private static func readPrismatic(
        _ reader: inout BinaryReader
    ) throws -> NIFPrismaticConstraint {
        try NIFPrismaticConstraint(
            frameA: readPrismaticFrame(&reader),
            frameB: readPrismaticFrame(&reader),
            minDistance: reader.readFloat32() * NIFCollisionModel.havokToEngineScale,
            maxDistance: reader.readFloat32() * NIFCollisionModel.havokToEngineScale,
            friction: reader.readFloat32(),
            motor: readMotor(&reader)
        )
    }

    private static func readPrismaticFrame(
        _ reader: inout BinaryReader
    ) throws -> NIFConstraintPrismaticFrame {
        try NIFConstraintPrismaticFrame(
            sliding: reader.readHavokAxis(),
            rotation: reader.readHavokAxis(),
            plane: reader.readHavokAxis(),
            pivot: reader.readHavokPoint()
        )
    }

    private static func readRagdoll(
        _ reader: inout BinaryReader
    ) throws -> NIFRagdollConstraint {
        try NIFRagdollConstraint(
            frameA: readRagdollFrame(&reader),
            frameB: readRagdollFrame(&reader),
            coneMaxAngle: reader.readFloat32(),
            planeMinAngle: reader.readFloat32(),
            planeMaxAngle: reader.readFloat32(),
            twistMinAngle: reader.readFloat32(),
            twistMaxAngle: reader.readFloat32(),
            maxFriction: reader.readFloat32(),
            motor: readMotor(&reader)
        )
    }

    private static func readRagdollFrame(
        _ reader: inout BinaryReader
    ) throws -> NIFConstraintRagdollFrame {
        try NIFConstraintRagdollFrame(
            twist: reader.readHavokAxis(),
            plane: reader.readHavokAxis(),
            motor: reader.readHavokAxis(),
            pivot: reader.readHavokPoint()
        )
    }

    /// `bhkMalleableConstraintCInfo` repeats the entity pair for the wrapped
    /// joint. The repeat is skipped: the outer `bhkConstraint` info already
    /// bound the same two bodies, and honoring a disagreeing copy would leave
    /// two answers for one joint.
    private static func readMalleable(
        _ reader: inout BinaryReader
    ) throws -> NIFConstraintData {
        let raw = try reader.readUInt32()
        guard let inner = NIFConstraintType(rawValue: raw), inner != .malleable else {
            throw NIFError.unsupported("malleable constraint wraps type \(raw)")
        }
        reader.skip(16) // repeated bhkConstraintCInfo
        let wrapped = try readData(type: inner, reader: &reader)
        return try .malleable(strength: reader.readFloat32(), wrapped: wrapped)
    }

    // MARK: - bhkConstraintMotorCInfo

    private static func readMotor(_ reader: inout BinaryReader) throws -> NIFConstraintMotor {
        let type = try reader.readUInt8()
        switch type {
        case 0:
            return .none
        case 1:
            return try .position(NIFPositionMotor(
                minForce: reader.readFloat32(),
                maxForce: reader.readFloat32(),
                tau: reader.readFloat32(),
                damping: reader.readFloat32(),
                proportionalRecoveryVelocity: reader.readFloat32(),
                constantRecoveryVelocity: reader.readFloat32(),
                isEnabled: reader.readHavokBool()
            ))
        case 2:
            return try .velocity(NIFVelocityMotor(
                minForce: reader.readFloat32(),
                maxForce: reader.readFloat32(),
                tau: reader.readFloat32(),
                targetVelocity: reader.readFloat32(),
                usesVelocityTarget: reader.readHavokBool(),
                isEnabled: reader.readHavokBool()
            ))
        case 3:
            return try .springDamper(NIFSpringDamperMotor(
                minForce: reader.readFloat32(),
                maxForce: reader.readFloat32(),
                springConstant: reader.readFloat32(),
                springDamping: reader.readFloat32(),
                isEnabled: reader.readHavokBool()
            ))
        default:
            // The payload length is unknown for an unknown motor type, so the
            // rest of the block cannot be trusted either.
            throw NIFError.unsupported("constraint motor type \(type)")
        }
    }
}
