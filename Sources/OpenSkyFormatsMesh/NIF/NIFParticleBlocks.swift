// Particle blocks that point at other objects: the bomb, the colliders, the
// recycle bound, mesh particles, and the controllers that animate one modifier
// parameter. The walk resolves their object refs into the system's space.
// Layout: docs/formats/nif-particles.md.

import Foundation
import OpenSkyFormatsCore
import simd

/// `NiPSysBombModifier`, before its bomb object is placed.
nonisolated public struct NIFBombModifier: Equatable, Sendable {
    public static let typeName = "NiPSysBombModifier"

    public let header: NIFParticleModifierHeader
    public let bombObjectRef: Int32
    public let axis: SIMD3<Float>
    public let decay: Float
    public let deltaV: Float
    public let decayType: UInt32
    public let symmetry: UInt32

    public init(reader: inout BinaryReader, header: NIFHeader) throws {
        self.header = try NIFParticleModifierHeader(reader: &reader, header: header)
        bombObjectRef = try reader.readNIFRef()
        axis = try reader.readVector3()
        decay = try reader.readFloat32()
        deltaV = try reader.readFloat32()
        decayType = try reader.readUInt32()
        symmetry = try reader.readUInt32()
    }

    /// The bomb at the origin of its object, whose transform is in system space.
    public func bomb(objectTransform: float4x4) -> ParticleBomb {
        ParticleBomb(
            position: .zero, axis: axis, decay: decay, deltaV: deltaV,
            decayType: ParticleBomb.Decay(rawValue: decayType) ?? .none,
            symmetry: ParticleBomb.Symmetry(rawValue: symmetry) ?? .spherical
        ).transformed(by: objectTransform)
    }
}

/// `NiPSysColliderManager`: the first collider of a chain.
nonisolated public struct NIFColliderManager: Equatable, Sendable {
    public static let typeName = "NiPSysColliderManager"

    public let header: NIFParticleModifierHeader
    public let colliderRef: Int32

    public init(reader: inout BinaryReader, header: NIFHeader) throws {
        self.header = try NIFParticleModifierHeader(reader: &reader, header: header)
        colliderRef = try reader.readNIFRef()
    }
}

/// nif.xml `NiPSysCollider` with its planar or spherical shape.
nonisolated public struct NIFParticleCollider: Equatable, Sendable {
    public static let planarType = "NiPSysPlanarCollider"
    public static let sphericalType = "NiPSysSphericalCollider"

    public enum Shape: Equatable, Sendable {
        /// Width and height along the two axes, in the collider object's space.
        case plane(width: Float, height: Float, xAxis: SIMD3<Float>, yAxis: SIMD3<Float>)
        case sphere(radius: Float)
    }

    public let bounce: Float
    /// Vanilla colliders never spawn; the spawn modifier is kept for the preview.
    public let spawnsOnCollide: Bool
    public let diesOnCollide: Bool
    public let spawnModifierRef: Int32
    public let managerRef: Int32
    public let nextColliderRef: Int32
    public let colliderObjectRef: Int32
    public let shape: Shape

    public init(reader: inout BinaryReader, planar: Bool) throws {
        bounce = try reader.readFloat32()
        spawnsOnCollide = try reader.readUInt8() != 0
        diesOnCollide = try reader.readUInt8() != 0
        spawnModifierRef = try reader.readNIFRef()
        managerRef = try reader.readNIFRef()
        nextColliderRef = try reader.readNIFRef()
        colliderObjectRef = try reader.readNIFRef()
        shape = if planar {
            try .plane(
                width: reader.readFloat32(), height: reader.readFloat32(),
                xAxis: reader.readVector3(), yAxis: reader.readVector3()
            )
        } else {
            try .sphere(radius: reader.readFloat32())
        }
    }

    /// The collider around its object's origin, whose transform is in system space.
    public func collider(objectTransform: float4x4) -> ParticleCollider {
        let local: ParticleCollider.Shape = switch shape {
        case let .plane(width, height, xAxis, yAxis):
            .plane(center: .zero, halfX: xAxis * width / 2, halfY: yAxis * height / 2)
        case let .sphere(radius):
            .sphere(center: .zero, radius: radius)
        }
        return ParticleCollider(bounce: bounce, diesOnCollide: diesOnCollide, shape: local)
            .transformed(by: objectTransform)
    }
}

/// `BSPSysRecycleBoundModifier`, before its bound object is placed.
nonisolated public struct NIFRecycleBoundModifier: Equatable, Sendable {
    public static let typeName = "BSPSysRecycleBoundModifier"

    public let header: NIFParticleModifierHeader
    public let offset: SIMD3<Float>
    public let extent: SIMD3<Float>
    /// -1 for a box around the system itself.
    public let boundObjectRef: Int32

    public init(reader: inout BinaryReader, header: NIFHeader) throws {
        self.header = try NIFParticleModifierHeader(reader: &reader, header: header)
        offset = try reader.readVector3()
        extent = try reader.readVector3()
        boundObjectRef = try reader.readNIFRef()
    }

    /// The offset is the box's lowest corner and the extent its size, from the
    /// bound object's position (docs/formats/nif-particles.md#recycle-bound).
    public func bound(objectPosition: SIMD3<Float>) -> ParticleRecycleBound {
        ParticleRecycleBound(minimum: objectPosition + offset, size: extent)
    }
}

/// `BSPSysStripUpdateModifier`: how often a strip particle adds a trail point.
nonisolated public enum NIFStripUpdateModifier {
    public static let typeName = "BSPSysStripUpdateModifier"
}

/// `NiPSysMeshUpdateModifier` and `BSPSysHavokUpdateModifier`: the shapes mesh
/// particles draw. The Havok one also names a modifier it drives.
nonisolated public struct NIFMeshUpdateModifier: Equatable, Sendable {
    public static let typeName = "NiPSysMeshUpdateModifier"
    public static let havokTypeName = "BSPSysHavokUpdateModifier"

    public let header: NIFParticleModifierHeader
    public let meshRefs: [Int32]
    /// -1 for the plain mesh update modifier.
    public let modifierRef: Int32

    public init(reader: inout BinaryReader, header: NIFHeader, havok: Bool) throws {
        self.header = try NIFParticleModifierHeader(reader: &reader, header: header)
        meshRefs = try reader.readNIFRefs(label: "particle mesh")
        modifierRef = havok ? try reader.readNIFRef() : -1
    }
}

/// `NiMeshPSysData`: particle data plus the pool of meshes the particles draw.
nonisolated public struct NIFMeshParticleData: Sendable {
    public static let typeName = "NiMeshPSysData"
    public static let systemTypeName = "NiMeshParticleSystem"

    public let data: NIFParticleData
    public let defaultPoolSize: UInt32
    public let fillsPoolsOnLoad: Bool
    public let generations: [UInt32]
    /// The `NiNode` whose children are the particle meshes.
    public let particleMeshesRef: Int32

    public init(reader: inout BinaryReader, header: NIFHeader) throws {
        data = try NIFParticleData(reader: &reader, header: header)
        defaultPoolSize = try reader.readUInt32()
        fillsPoolsOnLoad = try reader.readUInt8() != 0
        let count = try reader.readNIFCount(stride: 4, label: "generation")
        generations = try (0 ..< count).map { _ in try reader.readUInt32() }
        particleMeshesRef = try reader.readNIFRef()
    }
}

/// A modifier parameter controller before its keys are read.
nonisolated public struct NIFParticleModifierController: Equatable, Sendable {
    public let parameter: ParticleModifierController.Parameter
    public let base: NIFInterpolatedController
    public let modifierName: String?

    public init(
        parameter: ParticleModifierController.Parameter,
        reader: inout BinaryReader,
        header: NIFHeader
    ) throws {
        self.parameter = parameter
        base = try NIFInterpolatedController(reader: &reader)
        modifierName = try reader.readNIFString(header)
    }
}

/// `NiPSysUpdateCtlr`: tells the system to step its simulation each frame.
nonisolated public enum NIFParticleUpdateController {
    public static let typeName = "NiPSysUpdateCtlr"
}

nonisolated extension NIFBlockDecoders {
    static let particles: [String: Decode] = modifierControllers.merging(modifiers) { first, _ in
        first
    }.merging([
        NIFAgeDeathModifier.typeName: { try NIFAgeDeathModifier(reader: &$0, header: $1) },
        NIFGravityModifier.typeName: { try NIFGravityModifier(reader: &$0, header: $1) },
        NIFDragModifier.typeName: { try NIFDragModifier(reader: &$0, header: $1) },
        NIFInheritVelocityModifier.typeName: {
            try NIFInheritVelocityModifier(reader: &$0, header: $1)
        },
        NIFParticleUpdateController
            .typeName: { reader, _ in try NIFTimeController(reader: &reader) },
        NIFBombModifier.typeName: { try NIFBombModifier(reader: &$0, header: $1) },
        NIFColliderManager.typeName: { try NIFColliderManager(reader: &$0, header: $1) },
        NIFParticleCollider.planarType: { reader, _ in
            try NIFParticleCollider(reader: &reader, planar: true)
        },
        NIFParticleCollider.sphericalType: { reader, _ in
            try NIFParticleCollider(reader: &reader, planar: false)
        },
        NIFRecycleBoundModifier.typeName: { try NIFRecycleBoundModifier(reader: &$0, header: $1) },
        NIFStripUpdateModifier.typeName: { reader, header in
            try NIFParticleModifierDecoder.modifier(
                typeName: NIFStripUpdateModifier.typeName, reader: &reader, header: header
            )
        },
        NIFMeshUpdateModifier.havokTypeName: {
            try NIFMeshUpdateModifier(reader: &$0, header: $1, havok: true)
        },
        NIFMeshParticleData.typeName: { try NIFMeshParticleData(reader: &$0, header: $1) },
        NIFMeshParticleData.systemTypeName: { try NIFParticleSystem(reader: &$0, header: $1) }
    ]) { _, raw in raw }

    /// Each modifier as the engine reads it. The raw blocks above replace four of them,
    /// so the preview keeps their object refs.
    private static let modifiers = Dictionary(
        uniqueKeysWithValues: NIFParticleModifierDecoder.modifierTypes.map { typeName in
            (typeName, { reader, header in
                try NIFParticleModifierDecoder.modifier(
                    typeName: typeName, reader: &reader, header: header
                )
            } as Decode)
        }
    )

    private static let modifierControllers = Dictionary(
        uniqueKeysWithValues: ParticleModifierController.Parameter.allCases.map { parameter in
            (parameter.rawValue, { reader, header in
                try NIFParticleModifierController(
                    parameter: parameter,
                    reader: &reader,
                    header: header
                )
            } as Decode)
        }
    )
}

nonisolated extension ParticleModifier {
    init(_ header: NIFParticleModifierHeader, kind: Kind) {
        self.init(name: header.name, order: header.order, active: header.active, kind: kind)
    }
}
