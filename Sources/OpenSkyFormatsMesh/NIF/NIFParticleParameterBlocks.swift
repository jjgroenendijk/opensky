// The particle modifiers with parameters the simulation uses: age death, spawn,
// gravity, rotation, bound update, drag, inherit velocity, and sub-texture.
// Each body is read after `NIFParticleModifierHeader`.
// Layout: docs/formats/nif-particles.md#parameter-modifiers.

import Foundation
import OpenSkyFormatsCore
import simd

/// `NiPSysAgeDeathModifier`: particles die at the end of their life.
nonisolated public struct NIFAgeDeathModifier: Equatable, Sendable {
    public static let typeName = "NiPSysAgeDeathModifier"

    public let header: NIFParticleModifierHeader
    public let spawnsOnDeath: Bool
    public let spawnModifierRef: Int32

    public init(reader: inout BinaryReader, header: NIFHeader) throws {
        self.header = try NIFParticleModifierHeader(reader: &reader, header: header)
        spawnsOnDeath = try reader.readUInt8() != 0
        spawnModifierRef = try reader.readNIFRef()
    }
}

/// `NiPSysSpawnModifier`.
nonisolated public enum NIFSpawnModifier {
    public static let typeName = "NiPSysSpawnModifier"

    static func body(_ reader: inout BinaryReader) throws -> ParticleSpawn {
        let generations = try reader.readUInt16()
        let percentage = try reader.readFloat32()
        let minimum = try reader.readUInt16()
        let maximum = try reader.readUInt16()
        return try ParticleSpawn(
            generations: generations, percentage: percentage, minimumCount: minimum,
            maximumCount: max(maximum, minimum), speedVariation: reader.readFloat32(),
            directionVariation: reader.readFloat32(), lifeSpan: reader.readFloat32(),
            lifeSpanVariation: reader.readFloat32()
        )
    }
}

/// `NiPSysGravityModifier`, before its gravity object is placed.
nonisolated public struct NIFGravityModifier: Equatable, Sendable {
    public static let typeName = "NiPSysGravityModifier"

    public let header: NIFParticleModifierHeader
    public let gravityObjectRef: Int32
    /// At the origin of the gravity object, in that object's space.
    public let gravity: ParticleGravity

    public init(reader: inout BinaryReader, header: NIFHeader) throws {
        self.header = try NIFParticleModifierHeader(reader: &reader, header: header)
        (gravityObjectRef, gravity) = try Self.body(&reader)
    }

    static func body(_ reader: inout BinaryReader) throws -> (Int32, ParticleGravity) {
        let ref = try reader.readNIFRef()
        let axis = try reader.readVector3()
        let decay = try reader.readFloat32()
        let strength = try reader.readFloat32()
        let force = try ParticleGravity.Force(rawValue: reader.readUInt32()) ?? .planar
        return try (ref, ParticleGravity(
            position: .zero, axis: axis, decay: decay, strength: strength, force: force,
            turbulence: reader.readFloat32(), turbulenceScale: reader.readFloat32(),
            worldAligned: reader.readUInt8() != 0
        ))
    }
}

/// `NiPSysRotationModifier`.
nonisolated public enum NIFRotationModifier {
    public static let typeName = "NiPSysRotationModifier"

    static func body(_ reader: inout BinaryReader) throws -> ParticleRotation {
        try ParticleRotation(
            speed: reader.readFloat32(), speedVariation: reader.readFloat32(),
            angle: reader.readFloat32(), angleVariation: reader.readFloat32(),
            randomSpeedSign: reader.readUInt8() != 0, randomAxis: reader.readUInt8() != 0,
            axis: reader.readVector3()
        )
    }
}

/// `NiPSysDragModifier`, before its drag object is placed.
nonisolated public struct NIFDragModifier: Equatable, Sendable {
    public static let typeName = "NiPSysDragModifier"

    public let header: NIFParticleModifierHeader
    public let dragObjectRef: Int32
    /// At the origin of the drag object, in that object's space.
    public let drag: ParticleDrag

    public init(reader: inout BinaryReader, header: NIFHeader) throws {
        self.header = try NIFParticleModifierHeader(reader: &reader, header: header)
        (dragObjectRef, drag) = try Self.body(&reader)
    }

    static func body(_ reader: inout BinaryReader) throws -> (Int32, ParticleDrag) {
        let ref = try reader.readNIFRef()
        return try (ref, ParticleDrag(
            position: .zero, axis: reader.readVector3(), percentage: reader.readFloat32(),
            range: reader.readFloat32(), rangeFalloff: reader.readFloat32()
        ))
    }
}

/// `BSPSysInheritVelocityModifier`. OpenSky takes the velocity of the system
/// itself, not of the inherit object.
nonisolated public struct NIFInheritVelocityModifier: Equatable, Sendable {
    public static let typeName = "BSPSysInheritVelocityModifier"

    public let header: NIFParticleModifierHeader
    public let inheritObjectRef: Int32
    public let inherit: ParticleInheritVelocity

    public init(reader: inout BinaryReader, header: NIFHeader) throws {
        self.header = try NIFParticleModifierHeader(reader: &reader, header: header)
        (inheritObjectRef, inherit) = try Self.body(&reader)
    }

    static func body(_ reader: inout BinaryReader) throws -> (Int32, ParticleInheritVelocity) {
        let ref = try reader.readNIFRef()
        return try (ref, ParticleInheritVelocity(
            chance: reader.readFloat32(), multiplier: reader.readFloat32(),
            variation: reader.readFloat32()
        ))
    }
}

/// `BSPSysSubTexModifier`.
nonisolated public enum NIFSubTexModifier {
    public static let typeName = "BSPSysSubTexModifier"

    static func body(_ reader: inout BinaryReader) throws -> ParticleSubTexture {
        try ParticleSubTexture(
            startFrame: reader.readFloat32(), startFrameFudge: reader.readFloat32(),
            endFrame: reader.readFloat32(), loopStartFrame: reader.readFloat32(),
            loopStartFrameFudge: reader.readFloat32(), frameCount: reader.readFloat32(),
            frameCountFudge: reader.readFloat32()
        )
    }
}

nonisolated extension NIFParticleModifierDecoder {
    /// The kind of a parameter modifier, with its object at the system origin and no
    /// spawn on death. Nil for any other type.
    static func parameterKind(
        typeName: String,
        reader: inout BinaryReader
    ) throws -> ParticleModifier.Kind? {
        switch typeName {
        case NIFAgeDeathModifier.typeName:
            _ = try reader.readUInt8() // the spawn flag and ref; the walk resolves them
            _ = try reader.readNIFRef()
            return .ageDeath(spawn: nil)
        case NIFSpawnModifier.typeName: return try .spawn(NIFSpawnModifier.body(&reader))
        case NIFGravityModifier.typeName: return try .gravity(NIFGravityModifier.body(&reader).1)
        case NIFRotationModifier.typeName: return try .rotation(NIFRotationModifier.body(&reader))
        case "NiPSysPositionModifier": return .position
        case "NiPSysBoundUpdateModifier": return try .boundUpdate(skip: reader.readUInt16())
        case NIFDragModifier.typeName: return try .drag(NIFDragModifier.body(&reader).1)
        case NIFInheritVelocityModifier.typeName:
            return try .inheritVelocity(NIFInheritVelocityModifier.body(&reader).1)
        case NIFSubTexModifier.typeName: return try .subTex(NIFSubTexModifier.body(&reader))
        default: return nil
        }
    }
}
