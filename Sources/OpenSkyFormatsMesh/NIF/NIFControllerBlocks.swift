// Controller blocks beyond the transform and emitter controllers: shader and
// alpha property animation, lag bones, procedural lightning, bone LOD, and the
// controller manager with its object palette. Layout: docs/formats/nif-controllers.md.

import Foundation
import OpenSkyFormatsCore

/// A shader property controller: one interpolator drives one variable.
nonisolated public struct NIFShaderPropertyController: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case effectFloat = "BSEffectShaderPropertyFloatController"
        case effectColor = "BSEffectShaderPropertyColorController"
        case lightingFloat = "BSLightingShaderPropertyFloatController"
        case lightingColor = "BSLightingShaderPropertyColorController"

        public var isColor: Bool {
            self == .effectColor || self == .lightingColor
        }
    }

    public let kind: Kind
    public let base: NIFInterpolatedController
    /// nif.xml `EffectShaderControlledVariable`, `EffectShaderControlledColor`,
    /// `LightingShaderControlledFloat`, or `LightingShaderControlledColor`.
    public let variable: UInt32

    public init(kind: Kind, reader: inout BinaryReader) throws {
        self.kind = kind
        base = try NIFInterpolatedController(reader: &reader)
        variable = try reader.readUInt32()
    }
}

/// `NiFloatExtraDataController`: animates the `NiFloatExtraData` it names.
nonisolated public struct NIFExtraDataController: Equatable, Sendable {
    public static let typeName = "NiFloatExtraDataController"

    public let base: NIFInterpolatedController
    public let extraDataName: String?

    public init(reader: inout BinaryReader, header: NIFHeader) throws {
        base = try NIFInterpolatedController(reader: &reader)
        extraDataName = try reader.readNIFString(header)
    }
}

/// `BSLagBoneController`: the target bone trails its parent's motion.
nonisolated public struct NIFLagBoneController: Equatable, Sendable {
    public static let typeName = "BSLagBoneController"

    public let base: NIFTimeController
    public let linearVelocity: Float
    public let linearRotation: Float
    /// Engine units the bone may trail behind.
    public let maximumDistance: Float

    public init(reader: inout BinaryReader) throws {
        base = try NIFTimeController(reader: &reader)
        linearVelocity = try reader.readFloat32()
        linearRotation = try reader.readFloat32()
        maximumDistance = try reader.readFloat32()
    }
}

/// `BSProceduralLightningController`: the bolt a lightning shape draws.
nonisolated public struct NIFLightningController: Equatable, Sendable {
    public static let typeName = "BSProceduralLightningController"

    public let base: NIFTimeController
    /// Generation, mutation, subdivision, branches, branch variation, length,
    /// length variation, width, and arc offset, in that order.
    public let interpolatorRefs: [Int32]
    public let subdivisions: UInt16
    public let branches: UInt16
    public let branchVariation: UInt16
    public let length: Float
    public let lengthVariation: Float
    public let width: Float
    public let childWidthMultiplier: Float
    public let arcOffset: Float
    public let fadesMainBolt: Bool
    public let fadesChildBolts: Bool
    public let animatesArcOffset: Bool
    public let shaderPropertyRef: Int32

    public init(reader: inout BinaryReader) throws {
        base = try NIFTimeController(reader: &reader)
        interpolatorRefs = try (0 ..< 9).map { _ in try reader.readNIFRef() }
        subdivisions = try reader.readUInt16()
        branches = try reader.readUInt16()
        branchVariation = try reader.readUInt16()
        length = try reader.readFloat32()
        lengthVariation = try reader.readFloat32()
        width = try reader.readFloat32()
        childWidthMultiplier = try reader.readFloat32()
        arcOffset = try reader.readFloat32()
        fadesMainBolt = try reader.readUInt8() != 0
        fadesChildBolts = try reader.readUInt8() != 0
        animatesArcOffset = try reader.readUInt8() != 0
        shaderPropertyRef = try reader.readNIFRef()
    }
}

/// `NiBSBoneLODController`: which bones each level of detail keeps.
nonisolated public struct NIFBoneLODController: Equatable, Sendable {
    public static let typeName = "NiBSBoneLODController"

    public let base: NIFTimeController
    public let lod: UInt32
    /// One node list per level of detail.
    public let nodeGroups: [[Int32]]

    public init(reader: inout BinaryReader) throws {
        base = try NIFTimeController(reader: &reader)
        lod = try reader.readUInt32()
        let levels = try reader.readNIFCount(stride: 4, label: "bone LOD level")
        reader.skip(4) // node group count, which nif.xml does not use as a length
        nodeGroups = try (0 ..< levels).map { _ in try reader.readNIFRefs(label: "bone LOD node") }
    }
}

/// `NiControllerManager`: the named sequences that drive a model's controllers.
nonisolated public struct NIFControllerManager: Equatable, Sendable {
    public static let typeName = "NiControllerManager"

    public let base: NIFTimeController
    /// The sequences add up instead of replacing each other.
    public let cumulative: Bool
    public let sequenceRefs: [Int32]
    /// The `NiDefaultAVObjectPalette` that names the animated objects.
    public let objectPaletteRef: Int32

    public init(reader: inout BinaryReader) throws {
        base = try NIFTimeController(reader: &reader)
        cumulative = try reader.readUInt8() != 0
        sequenceRefs = try reader.readNIFRefs(label: "controller sequence")
        objectPaletteRef = try reader.readNIFRef()
    }
}

/// `NiDefaultAVObjectPalette`: object names mapped to their blocks.
nonisolated public struct NIFObjectPalette: Equatable, Sendable {
    public static let typeName = "NiDefaultAVObjectPalette"

    public let sceneRef: Int32
    public let objects: [Entry]

    public struct Entry: Equatable, Sendable {
        public let name: String
        public let objectRef: Int32
    }

    public init(reader: inout BinaryReader) throws {
        sceneRef = try reader.readNIFRef()
        let count = try reader.readNIFCount(stride: 8, label: "palette object")
        objects = try (0 ..< count).map { _ in
            try Entry(name: reader.readNIFSizedString(), objectRef: reader.readNIFRef())
        }
    }

    /// The block of the object named `name`, compared without case.
    public func block(named name: String) -> Int32? {
        objects.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.objectRef
    }
}

/// A controller with one interpolator and no fields of its own, by type.
nonisolated public struct NIFPlainController: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        /// Animates `NiAlphaProperty`'s alpha test threshold, 0 to 255.
        case alphaTestReference = "BSNiAlphaPropertyTestRefController"
        /// Animates an `NiCamera`'s horizontal field of view, in degrees.
        case frustumFieldOfView = "BSFrustumFOVController"
    }

    public let kind: Kind
    public let base: NIFInterpolatedController
}

nonisolated extension NIFBlockDecoders {
    static let controllers: [String: Decode] = shaderControllers
        .merging(plainControllers) { first, _ in first }
        .merging([
            NIFExtraDataController
                .typeName: { try NIFExtraDataController(reader: &$0, header: $1) },
            NIFLagBoneController
                .typeName: { reader, _ in try NIFLagBoneController(reader: &reader) },
            NIFLightningController.typeName: { reader, _ in
                try NIFLightningController(reader: &reader)
            },
            NIFBoneLODController
                .typeName: { reader, _ in try NIFBoneLODController(reader: &reader) },
            NIFControllerManager
                .typeName: { reader, _ in try NIFControllerManager(reader: &reader) },
            NIFObjectPalette.typeName: { reader, _ in try NIFObjectPalette(reader: &reader) }
        ]) { first, _ in first }
        .merging(interpolators) { first, _ in first }

    private static let shaderControllers = Dictionary(
        uniqueKeysWithValues: NIFShaderPropertyController.Kind.allCases.map { kind in
            (kind.rawValue, { reader, _ in
                try NIFShaderPropertyController(kind: kind, reader: &reader)
            } as Decode)
        }
    )

    private static let plainControllers = Dictionary(
        uniqueKeysWithValues: NIFPlainController.Kind.allCases.map { kind in
            (kind.rawValue, { reader, _ in
                try NIFPlainController(kind: kind, base: NIFInterpolatedController(reader: &reader))
            } as Decode)
        }
    )
}
