// Decodes the bhkConstraint blocks in a rigid body's constraint list. Field
// order is the Fallout 3 and later branch of each nif.xml CInfo struct, which
// every Skyrim SE stream takes. Layout: docs/formats/nif-collision.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public enum NIFConstraintDecoder: Sendable {
    /// Constraint block types this decoder reads, keyed to the `hkConstraintType`
    /// the block's payload follows.
    public static let types: [String: NIFConstraintType] = [
        "bhkBallAndSocketConstraint": .ballAndSocket,
        "bhkHingeConstraint": .hinge,
        "bhkLimitedHingeConstraint": .limitedHinge,
        "bhkPrismaticConstraint": .prismatic,
        "bhkRagdollConstraint": .ragdoll,
        "bhkStiffSpringConstraint": .stiffSpring,
        "bhkMalleableConstraint": .malleable
    ]

    /// `bhkBreakableConstraint` wraps a joint of any type in `types`.
    public static let breakableType = "bhkBreakableConstraint"

    /// Every joint `block` holds: one, or one per link of a ball-and-socket chain.
    /// Throws `NIFError.unsupported` for a constraint class this decoder does not
    /// read, so the caller tallies it by block type and keeps the body.
    public static func decodeAll(
        block: NIFFile.Block,
        index: Int
    ) throws -> [NIFCollisionConstraint] {
        var reader = BinaryReader(block.data)
        if block.typeName == NIFBallSocketChain.typeName {
            return try NIFBallSocketChain(reader: &reader).constraints(block: index)
        }
        return try [decode(reader: &reader, typeName: block.typeName, index: index)]
    }

    static func decode(
        reader: inout BinaryReader,
        typeName: String,
        index: Int
    ) throws -> NIFCollisionConstraint {
        let type = types[typeName]
        guard type != nil || typeName == breakableType else {
            throw NIFError.unsupported("constraint class \(typeName)")
        }
        let info = try readConstraintInfo(&reader)
        let data = try type
            .map { try readData(type: $0, reader: &reader) } ?? readBreakable(&reader)
        return NIFCollisionConstraint(
            block: index,
            entityA: info.entityA,
            entityB: info.entityB,
            priority: info.priority,
            data: data
        )
    }

    /// nif.xml `bhkWrappedConstraintData`, then the break threshold and flag.
    private static func readBreakable(_ reader: inout BinaryReader) throws -> NIFConstraintData {
        let raw = try reader.readUInt32()
        guard let inner = NIFConstraintType(rawValue: raw) else {
            throw NIFError.unsupported("breakable constraint wraps type \(raw)")
        }
        reader.skip(16) // repeated bhkConstraintCInfo
        let wrapped = try readData(type: inner, reader: &reader)
        return try .breakable(
            threshold: reader.readFloat32(), removedWhenBroken: reader.readUInt8() != 0,
            wrapped: wrapped
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
            // nif.xml order: min force, max force, tau, damping, then two
            // recovery velocities. Only max force and tau are kept.
            reader.skip(4)
            let maxForce = try reader.readFloat32()
            let tau = try reader.readFloat32()
            reader.skip(12)
            return try .position(NIFPositionMotor(
                maxForce: maxForce, tau: tau, isEnabled: reader.readHavokBool()
            ))
        case 2:
            // Four floats and a velocity-target flag before the enabled flag.
            reader.skip(17)
            return try .velocity(NIFVelocityMotor(isEnabled: reader.readHavokBool()))
        case 3:
            // Min force, max force, spring constant, spring damping.
            reader.skip(8)
            let springConstant = try reader.readFloat32()
            reader.skip(4)
            return try .springDamper(NIFSpringDamperMotor(
                springConstant: springConstant, isEnabled: reader.readHavokBool()
            ))
        default:
            // The payload length is unknown for an unknown motor type, so the
            // rest of the block cannot be trusted either.
            throw NIFError.unsupported("constraint motor type \(type)")
        }
    }
}
