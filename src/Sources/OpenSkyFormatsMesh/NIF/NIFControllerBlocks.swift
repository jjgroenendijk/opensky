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

        var isColor: Bool {
            self == .effectColor || self == .lightingColor
        }
    }

    let kind: Kind
    let base: NIFInterpolatedController
    /// nif.xml `EffectShaderControlledVariable`, `EffectShaderControlledColor`,
    /// `LightingShaderControlledFloat`, or `LightingShaderControlledColor`.
    let variable: UInt32

    init(kind: Kind, reader: inout BinaryReader) throws {
        self.kind = kind
        base = try NIFInterpolatedController(reader: &reader)
        variable = try reader.readUInt32()
    }
}

/// `NiFloatExtraDataController`: animates the `NiFloatExtraData` it names.
nonisolated struct NIFExtraDataController: Equatable, Sendable {
    static let typeName = "NiFloatExtraDataController"

    let base: NIFInterpolatedController
    let extraDataName: String?

    init(reader: inout BinaryReader, header: NIFHeader) throws {
        base = try NIFInterpolatedController(reader: &reader)
        extraDataName = try reader.readNIFString(header)
    }
}

/// `BSLagBoneController`: the target bone trails its parent's motion.
nonisolated struct NIFLagBoneController: Equatable, Sendable {
    static let typeName = "BSLagBoneController"

    let base: NIFTimeController
    let linearVelocity: Float
    let linearRotation: Float
    /// Engine units the bone may trail behind.
    let maximumDistance: Float

    init(reader: inout BinaryReader) throws {
        base = try NIFTimeController(reader: &reader)
        linearVelocity = try reader.readFloat32()
        linearRotation = try reader.readFloat32()
        maximumDistance = try reader.readFloat32()
    }
}

/// `BSProceduralLightningController`: the bolt a lightning shape draws.
nonisolated public struct NIFLightningController: Equatable, Sendable {
    static let typeName = "BSProceduralLightningController"

    public let base: NIFTimeController
    /// Generation, mutation, subdivision, branches, branch variation, length,
    /// length variation, width, and arc offset, in that order.
    let interpolatorRefs: [Int32]
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
    let animatesArcOffset: Bool
    public let shaderPropertyRef: Int32

    init(reader: inout BinaryReader) throws {
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
nonisolated struct NIFBoneLODController: Equatable, Sendable {
    static let typeName = "NiBSBoneLODController"

    let base: NIFTimeController
    let lod: UInt32
    /// One node list per level of detail.
    let nodeGroups: [[Int32]]

    init(reader: inout BinaryReader) throws {
        base = try NIFTimeController(reader: &reader)
        lod = try reader.readUInt32()
        let levels = try reader.readNIFCount(stride: 4, label: "bone LOD level")
        reader.skip(4) // node group count, which nif.xml does not use as a length
        nodeGroups = try (0 ..< levels).map { _ in try reader.readNIFRefs(label: "bone LOD node") }
    }
}

/// `NiControllerManager`: the named sequences that drive a model's controllers.
nonisolated struct NIFControllerManager: Equatable, Sendable {
    static let typeName = "NiControllerManager"

    let base: NIFTimeController
    /// The sequences add up instead of replacing each other.
    let cumulative: Bool
    let sequenceRefs: [Int32]
    /// The `NiDefaultAVObjectPalette` that names the animated objects.
    let objectPaletteRef: Int32

    init(reader: inout BinaryReader) throws {
        base = try NIFTimeController(reader: &reader)
        cumulative = try reader.readUInt8() != 0
        sequenceRefs = try reader.readNIFRefs(label: "controller sequence")
        objectPaletteRef = try reader.readNIFRef()
    }
}

/// `NiDefaultAVObjectPalette`: object names mapped to their blocks.
nonisolated struct NIFObjectPalette: Equatable, Sendable {
    static let typeName = "NiDefaultAVObjectPalette"

    let sceneRef: Int32
    let objects: [Entry]

    struct Entry: Equatable, Sendable {
        let name: String
        let objectRef: Int32
    }

    init(reader: inout BinaryReader) throws {
        sceneRef = try reader.readNIFRef()
        let count = try reader.readNIFCount(stride: 8, label: "palette object")
        objects = try (0 ..< count).map { _ in
            try Entry(name: reader.readNIFSizedString(), objectRef: reader.readNIFRef())
        }
    }

    /// The block of the object named `name`, compared without case.
    func block(named name: String) -> Int32? {
        objects.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.objectRef
    }
}

/// A controller with one interpolator and no fields of its own, by type.
nonisolated struct NIFPlainController: Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        /// Animates `NiAlphaProperty`'s alpha test threshold, 0 to 255.
        case alphaTestReference = "BSNiAlphaPropertyTestRefController"
        /// Animates an `NiCamera`'s horizontal field of view, in degrees.
        case frustumFieldOfView = "BSFrustumFOVController"
    }

    let kind: Kind
    let base: NIFInterpolatedController
}

nonisolated extension NIFBlockDecoders {
    enum Controllers {
        static let controllers = NIFBlockDecoders.joined([
            ownControllers,
            Interpolators.interpolators
        ])

        private static let ownControllers: [String: Decode] = shaderControllers
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
                    try NIFPlainController(
                        kind: kind,
                        base: NIFInterpolatedController(reader: &reader)
                    )
                } as Decode)
            }
        )
    }
}
