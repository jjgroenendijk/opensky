// Particle modifier + emitter block parsers. Every NiPSysModifier subclass
// shares a base run (Name string ref, Order, Target ptr, Active flag); every
// NiPSysEmitter subclass adds the birth-parameter run (speed/variation,
// declination, planar angle, initial color/radius, life span). NiPSysVolume
// emitters (box/cylinder/sphere) then add an emitter-object ptr and their
// shape params; the mesh emitter adds mesh refs + a velocity type. The Target
// ptr and the volume emitter object ptr are read past but not kept — static
// decode only needs identity + shape params. Concrete modifiers are mapped to
// ParticleModifier.Kind; a type this decoder does not model becomes
// `.unsupported(typeName:)` (skip + note, never throw) while malformed bytes
// inside a known block throw NIFError.
//
// Reference: NifTools nif.xml (NiPSysModifier, NiPSysEmitter,
// NiPSysVolumeEmitter and the concrete emitter/modifier blocks; ForceType,
// VelocityType and NiPSysModifierOrder are 32-bit).
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
// Layout documented in docs/formats/nif-particles.md.

import Foundation
import simd

nonisolated enum NIFParticleModifierDecoder {
    /// nif.xml NiPSysEmitter subclasses used by Skyrim particle assets.
    static let emitterTypes: Set = [
        "NiPSysBoxEmitter", "NiPSysCylinderEmitter",
        "NiPSysSphereEmitter", "NiPSysMeshEmitter"
    ]

    static func isEmitter(_ typeName: String) -> Bool {
        emitterTypes.contains(typeName)
    }

    /// Decodes a NiPSysEmitter subclass block into an engine emitter.
    static func emitter(
        typeName: String,
        data: Data,
        header: NIFHeader
    ) throws -> ParticleEmitter {
        var reader = BinaryReader(data)
        let base = try ModifierBase(reader: &reader, header: header)
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
    static func modifier(
        typeName: String,
        data: Data,
        header: NIFHeader
    ) throws -> ParticleModifier {
        var reader = BinaryReader(data)
        let base = try ModifierBase(reader: &reader, header: header)
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
            let velocityType = try reader.readUInt32()
            // Emission type + emission axis follow; not needed for decode.
            return .mesh(meshRefs: refs, initialVelocityType: velocityType)
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
        "BSPSysSimpleColorModifier": .simpleColor,
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

/// Shared NiPSysModifier prefix: name (string ref), order, target ptr
/// (skipped), active flag.
nonisolated private struct ModifierBase {
    let name: String?
    let order: UInt32
    let active: Bool

    init(reader: inout BinaryReader, header: NIFHeader) throws {
        let nameIndex = try reader.readUInt32()
        if nameIndex != .max, Int(nameIndex) < header.strings.count {
            name = header.strings[Int(nameIndex)]
        } else {
            name = nil // unnamed or exporter garbage — stay lenient
        }
        order = try reader.readUInt32()
        reader.skip(4) // Target ptr (NiParticleSystem parent), unused
        active = try reader.readUInt8() != 0
    }
}

/// Shared NiPSysEmitter birth-parameter run, read after ModifierBase.
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
