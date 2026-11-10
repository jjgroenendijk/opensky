// Particle blocks that point at other objects: the bomb, the colliders, the
// recycle bound, mesh particles, and the controllers that animate one modifier
// parameter. The walk resolves their object refs into the system's space.
// Layout: docs/formats/nif-particles.md.

import Foundation
import OpenSkyFormatsCore
import simd

/// `NiPSysBombModifier`, before its bomb object is placed.
nonisolated struct NIFBombModifier: Equatable, Sendable {
    static let typeName = "NiPSysBombModifier"

    let header: NIFParticleModifierHeader
    let bombObjectRef: Int32
    let axis: SIMD3<Float>
    let decay: Float
    let deltaV: Float
    let decayType: UInt32
    let symmetry: UInt32

    init(reader: inout BinaryReader, header: NIFHeader) throws {
        self.header = try NIFParticleModifierHeader(reader: &reader, header: header)
        bombObjectRef = try reader.readNIFRef()
        axis = try reader.readVector3()
        decay = try reader.readFloat32()
        deltaV = try reader.readFloat32()
        decayType = try reader.readUInt32()
        symmetry = try reader.readUInt32()
    }

    /// The bomb at the origin of its object, whose transform is in system space.
    func bomb(objectTransform: float4x4) -> ParticleBomb {
        ParticleBomb(
            position: .zero, axis: axis, decay: decay, deltaV: deltaV,
            decayType: ParticleBomb.Decay(rawValue: decayType) ?? .none,
            symmetry: ParticleBomb.Symmetry(rawValue: symmetry) ?? .spherical
        ).transformed(by: objectTransform)
    }
}

/// `NiPSysColliderManager`: the first collider of a chain.
nonisolated struct NIFColliderManager: Equatable, Sendable {
    static let typeName = "NiPSysColliderManager"

    let header: NIFParticleModifierHeader
    let colliderRef: Int32

    init(reader: inout BinaryReader, header: NIFHeader) throws {
        self.header = try NIFParticleModifierHeader(reader: &reader, header: header)
        colliderRef = try reader.readNIFRef()
    }
}

/// nif.xml `NiPSysCollider` with its planar or spherical shape.
nonisolated struct NIFParticleCollider: Equatable, Sendable {
    static let planarType = "NiPSysPlanarCollider"
    static let sphericalType = "NiPSysSphericalCollider"

    enum Shape: Equatable, Sendable {
        /// Width and height along the two axes, in the collider object's space.
        case plane(width: Float, height: Float, xAxis: SIMD3<Float>, yAxis: SIMD3<Float>)
        case sphere(radius: Float)
    }

    let bounce: Float
    /// Vanilla colliders never spawn; the spawn modifier is kept for the preview.
    let spawnsOnCollide: Bool
    let diesOnCollide: Bool
    let spawnModifierRef: Int32
    let managerRef: Int32
    let nextColliderRef: Int32
    let colliderObjectRef: Int32
    let shape: Shape

    init(reader: inout BinaryReader, planar: Bool) throws {
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
    func collider(objectTransform: float4x4) -> ParticleCollider {
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
nonisolated struct NIFRecycleBoundModifier: Equatable, Sendable {
    static let typeName = "BSPSysRecycleBoundModifier"

    let header: NIFParticleModifierHeader
    let offset: SIMD3<Float>
    let extent: SIMD3<Float>
    /// -1 for a box around the system itself.
    let boundObjectRef: Int32

    init(reader: inout BinaryReader, header: NIFHeader) throws {
        self.header = try NIFParticleModifierHeader(reader: &reader, header: header)
        offset = try reader.readVector3()
        extent = try reader.readVector3()
        boundObjectRef = try reader.readNIFRef()
    }

    /// The offset is the box's lowest corner and the extent its size, from the
    /// bound object's position (docs/formats/nif-particles.md#recycle-bound).
    func bound(objectPosition: SIMD3<Float>) -> ParticleRecycleBound {
        ParticleRecycleBound(minimum: objectPosition + offset, size: extent)
    }
}

/// `BSPSysStripUpdateModifier`: how often a strip particle adds a trail point.
nonisolated enum NIFStripUpdateModifier {
    static let typeName = "BSPSysStripUpdateModifier"
}

/// `NiPSysMeshUpdateModifier` and `BSPSysHavokUpdateModifier`: the shapes mesh
/// particles draw. The Havok one also names a modifier it drives.
nonisolated struct NIFMeshUpdateModifier: Equatable, Sendable {
    static let typeName = "NiPSysMeshUpdateModifier"
    static let havokTypeName = "BSPSysHavokUpdateModifier"

    let header: NIFParticleModifierHeader
    let meshRefs: [Int32]
    /// -1 for the plain mesh update modifier.
    let modifierRef: Int32

    init(reader: inout BinaryReader, header: NIFHeader, havok: Bool) throws {
        self.header = try NIFParticleModifierHeader(reader: &reader, header: header)
        meshRefs = try reader.readNIFRefs(label: "particle mesh")
        modifierRef = havok ? try reader.readNIFRef() : -1
    }
}

/// `NiMeshPSysData`: particle data plus the pool of meshes the particles draw.
nonisolated struct NIFMeshParticleData: Sendable {
    static let typeName = "NiMeshPSysData"
    static let systemTypeName = "NiMeshParticleSystem"

    let data: NIFParticleData
    let defaultPoolSize: UInt32
    let fillsPoolsOnLoad: Bool
    let generations: [UInt32]
    /// The `NiNode` whose children are the particle meshes.
    let particleMeshesRef: Int32

    init(reader: inout BinaryReader, header: NIFHeader) throws {
        data = try NIFParticleData(reader: &reader, header: header)
        defaultPoolSize = try reader.readUInt32()
        fillsPoolsOnLoad = try reader.readUInt8() != 0
        let count = try reader.readNIFCount(stride: 4, label: "generation")
        generations = try (0 ..< count).map { _ in try reader.readUInt32() }
        particleMeshesRef = try reader.readNIFRef()
    }
}

/// A modifier parameter controller before its keys are read.
nonisolated struct NIFParticleModifierController: Equatable, Sendable {
    let parameter: ParticleModifierController.Parameter
    let base: NIFInterpolatedController
    let modifierName: String?

    init(
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
nonisolated enum NIFParticleUpdateController {
    static let typeName = "NiPSysUpdateCtlr"
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
