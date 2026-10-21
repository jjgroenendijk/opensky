// Particle modifier and emitter blocks. A modifier type this decoder does not
// model becomes `.unsupported(typeName:)` and does not throw; malformed bytes
// in a known block do throw. Layout: docs/formats/nif-particles.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public enum NIFParticleModifierDecoder: Sendable {
    /// nif.xml NiPSysEmitter subclasses used by Skyrim particle assets.
    public static let emitterTypes: Set = [
        "NiPSysBoxEmitter", "NiPSysCylinderEmitter",
        "NiPSysSphereEmitter", "NiPSysMeshEmitter"
    ]

    public static func isEmitter(_ typeName: String) -> Bool {
        emitterTypes.contains(typeName)
    }

    /// Decodes a NiPSysEmitter subclass block into an engine emitter.
    public static func emitter(
        typeName: String,
        data: Data,
        header: NIFHeader
    ) throws -> ParticleEmitter {
        var reader = BinaryReader(data)
        let base = try NIFParticleModifierHeader(reader: &reader, header: header)
        let birth = try EmitterBase(reader: &reader)
        let shape = try readShape(typeName: typeName, reader: &reader)
        return ParticleEmitter(
            name: base.name,
            order: base.order,
            active: base.active,
            speed: birth.speed,
            speedVariation: birth.speedVariation,
            declination: birth.declination,
            declinationVariation: birth.declinationVariation,
            planarAngle: birth.planarAngle,
            planarAngleVariation: birth.planarAngleVariation,
            initialColor: birth.initialColor,
            initialRadius: birth.initialRadius,
            radiusVariation: birth.radiusVariation,
            lifeSpan: birth.lifeSpan,
            lifeSpanVariation: birth.lifeSpanVariation,
            shape: shape
        )
    }

    /// Decodes a non-emitter NiPSysModifier subclass into an engine modifier.
    /// Unknown types return `.unsupported` without reading past the base.
    public static func modifier(
        typeName: String,
        data: Data,
        header: NIFHeader
    ) throws -> ParticleModifier {
        var reader = BinaryReader(data)
        return try modifier(typeName: typeName, reader: &reader, header: header)
    }

    public static func modifier(
        typeName: String,
        reader: inout BinaryReader,
        header: NIFHeader
    ) throws -> ParticleModifier {
        let base = try NIFParticleModifierHeader(reader: &reader, header: header)
        let kind = try readKind(typeName: typeName, reader: &reader)
        return ParticleModifier(
            name: base.name,
            order: base.order,
            active: base.active,
            kind: kind
        )
    }

    private static func readShape(
        typeName: String,
        reader: inout BinaryReader
    ) throws -> ParticleEmitter.Shape {
        switch typeName {
        case "NiPSysBoxEmitter":
            reader.skip(4) // Emitter Object ptr (NiPSysVolumeEmitter)
            return try .box(
                width: reader.readFloat32(),
                height: reader.readFloat32(),
                depth: reader.readFloat32()
            )
        case "NiPSysCylinderEmitter":
            reader.skip(4) // Emitter Object ptr
            return try .cylinder(
                radius: reader.readFloat32(),
                height: reader.readFloat32()
            )
        case "NiPSysSphereEmitter":
            reader.skip(4) // Emitter Object ptr
            return try .sphere(radius: reader.readFloat32())
        case "NiPSysMeshEmitter":
            // Mesh emitter inherits NiPSysEmitter directly (no volume ptr).
            let count = try Int(reader.readUInt32())
            guard count >= 0, count * 4 <= reader.bytesRemaining else {
                throw NIFError.malformed(
                    "emitter mesh count \(count) exceeds block size"
                )
            }
            var refs: [Int32] = []
            refs.reserveCapacity(count)
            for _ in 0 ..< count {
                try refs.append(Int32(bitPattern: reader.readUInt32()))
            }
            let velocity = try reader.readUInt32()
            let emitFrom = try reader.readUInt32()
            let axis = try reader.readVector3()
            return .mesh(MeshEmitterSource(
                meshRefs: refs,
                velocity: MeshEmitterSource.Velocity(rawValue: velocity) ?? .normals,
                emitFrom: MeshEmitterSource.EmitFrom(rawValue: emitFrom) ?? .vertices,
                emissionAxis: axis
            ))
        default:
            throw NIFError.malformed("unexpected emitter type \(typeName)")
        }
    }

    /// Modifier types with no parameters this decoder keeps: identity alone.
    private static let simpleKinds: [String: ParticleModifier.Kind] = [
        "NiPSysAgeDeathModifier": .ageDeath,
        "NiPSysSpawnModifier": .spawn,
        "NiPSysRotationModifier": .rotation,
        "NiPSysPositionModifier": .position,
        "NiPSysBoundUpdateModifier": .boundUpdate,
        "NiPSysDragModifier": .drag,
        "BSPSysInheritVelocityModifier": .inheritVelocity,
        "BSPSysSubTexModifier": .subTex
    ]

    private static func readKind(
        typeName: String,
        reader: inout BinaryReader
    ) throws -> ParticleModifier.Kind {
        if let simple = simpleKinds[typeName] {
            return simple
        }
        switch typeName {
        case "NiPSysGravityModifier":
            reader.skip(4) // Gravity Object ptr
            let axis = try reader.readVector3()
            reader.skip(4) // Decay
            let strength = try reader.readFloat32()
            return .gravity(axis: axis, strength: strength)
        case "BSPSysSimpleColorModifier":
            let fades = try SIMD2(reader.readFloat32(), reader.readFloat32())
            let stops = try SIMD4(
                reader.readFloat32(), reader.readFloat32(), reader.readFloat32(),
                reader.readFloat32()
            )
            var colours: [SIMD4<Float>] = []
            for _ in 0 ..< 3 {
                try colours.append(SIMD4(
                    reader.readFloat32(), reader.readFloat32(), reader.readFloat32(),
                    reader.readFloat32()
                ))
            }
            return .simpleColour(ParticleColourRamp(fades: fades, stops: stops, colours: colours))
        case "BSWindModifier":
            return try .wind(strength: reader.readFloat32())
        case "BSPSysScaleModifier":
            let count = try Int(reader.readUInt32())
            guard count >= 0, count * 4 <= reader.bytesRemaining else {
                throw NIFError.malformed(
                    "scale count \(count) exceeds block size"
                )
            }
            var scales: [Float] = []
            scales.reserveCapacity(count)
            for _ in 0 ..< count {
                try scales.append(reader.readFloat32())
            }
            return .scale(scales: scales)
        case NIFStripUpdateModifier.typeName:
            return try .stripUpdate(interval: reader.readFloat32())
        case NIFMeshUpdateModifier.typeName, NIFMeshUpdateModifier.havokTypeName:
            return try .meshUpdate(meshRefs: reader.readNIFRefs(label: "particle mesh"))
        case "BSPSysLODModifier":
            return try .lod(
                beginDistance: reader.readFloat32(),
                endDistance: reader.readFloat32(),
                endEmitScale: reader.readFloat32(),
                endSize: reader.readFloat32()
            )
        default:
            // Skip + note: an unmodelled modifier must not fail the whole
            // system decode (AGENTS.md reverse-engineering discipline).
            return .unsupported(typeName: typeName)
        }
    }
}

/// nif.xml `NiPSysModifier`: name, order, target system, and the active flag.
nonisolated public struct NIFParticleModifierHeader: Equatable, Sendable {
    public let name: String?
    public let order: UInt32
    public let targetRef: Int32
    public let active: Bool

    public init(reader: inout BinaryReader, header: NIFHeader) throws {
        name = try reader.readNIFString(header)
        order = try reader.readUInt32()
        targetRef = try reader.readNIFRef()
        active = try reader.readUInt8() != 0
    }
}

/// Shared NiPSysEmitter birth-parameter run, read after `NIFParticleModifierHeader`.
nonisolated private struct EmitterBase {
    let speed: Float
    let speedVariation: Float
    let declination: Float
    let declinationVariation: Float
    let planarAngle: Float
    let planarAngleVariation: Float
    let initialColor: SIMD4<Float>
    let initialRadius: Float
    let radiusVariation: Float
    let lifeSpan: Float
    let lifeSpanVariation: Float

    init(reader: inout BinaryReader) throws {
        speed = try reader.readFloat32()
        speedVariation = try reader.readFloat32()
        declination = try reader.readFloat32()
        declinationVariation = try reader.readFloat32()
        planarAngle = try reader.readFloat32()
        planarAngleVariation = try reader.readFloat32()
        initialColor = try SIMD4(
            reader.readFloat32(), reader.readFloat32(),
            reader.readFloat32(), reader.readFloat32()
        )
        initialRadius = try reader.readFloat32()
        radiusVariation = try reader.readFloat32() // since 10.4.0.1, present
        lifeSpan = try reader.readFloat32()
        lifeSpanVariation = try reader.readFloat32()
    }
}
