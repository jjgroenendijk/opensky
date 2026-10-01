// The blending generators. A blender runs several children at once and mixes
// their poses; `m_blendParameter` is usually bound to a variable such as
// `Speed`, and each child's `m_weight` places it along that parameter.
// Byte map: docs/formats/hkx-behavior-nodes.md.

import Foundation

/// The members `hkbBlenderGenerator` declares, shared with the subclass
/// `hkbPoseMatchingGenerator` so both read one layout rather than two copies.
nonisolated public struct HKBBlenderFields: Equatable, Sendable {
    /// Below this weight a child is dropped in favour of the reference pose.
    public let referencePoseWeightThreshold: Float
    /// The value children are weighted against; normally variable-bound.
    public let blendParameter: Float
    public let minCyclicBlendParameter: Float
    public let maxCyclicBlendParameter: Float
    /// Child whose clip time the others follow, or -1 for no sync.
    public let indexOfSyncMasterChild: Int
    /// `hkbBlenderGenerator::BlenderFlags`: bit 0 sync cycles, bit 1 smooth
    /// generator weights, bit 2 parametric blend, bit 3 velocity sync.
    public let flags: Int
    /// When true the last child is subtracted from the blend rather than added.
    public let subtractLastChild: Bool
    /// `hkbBlenderGeneratorChild` objects, index-preserving.
    public let children: [HKXPointerTarget?]

    private static let thresholdField = HKXField(
        0x48, "m_referencePoseWeightThreshold"
    )
    private static let blendParameterField = HKXField(0x4C, "m_blendParameter")
    private static let minCyclicField = HKXField(0x50, "m_minCyclicBlendParameter")
    private static let maxCyclicField = HKXField(0x54, "m_maxCyclicBlendParameter")
    private static let syncMasterField = HKXField(0x58, "m_indexOfSyncMasterChild")
    private static let flagsField = HKXField(0x5A, "m_flags")
    private static let subtractLastChildField = HKXField(0x5C, "m_subtractLastChild")
    private static let childrenField = HKXField(0x60, "m_children")

    public static func decode(_ cursor: inout HKXObjectCursor) -> HKBBlenderFields {
        HKBBlenderFields(
            referencePoseWeightThreshold: cursor.float32(at: thresholdField) ?? 0,
            blendParameter: cursor.float32(at: blendParameterField) ?? 0,
            minCyclicBlendParameter: cursor.float32(at: minCyclicField) ?? 0,
            maxCyclicBlendParameter: cursor.float32(at: maxCyclicField) ?? 0,
            indexOfSyncMasterChild: cursor.int16(at: syncMasterField) ?? -1,
            flags: cursor.int16(at: flagsField) ?? 0,
            subtractLastChild: cursor.bool(at: subtractLastChildField) ?? false,
            children: cursor.pointerArray(at: childrenField)
        )
    }

    public var references: [HKBReference] {
        HKBReference.each("m_children", children)
    }

    public var summary: String {
        "\(children.count) children, blend parameter \(blendParameter), flags \(flags)"
    }
}

/// Decoded `hkbBlenderGenerator`, size 160.
nonisolated public struct HKBBlenderGenerator: HKBClass, Equatable, Sendable {
    public let node: HKBNodeHeader
    public let blender: HKBBlenderFields
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbBlenderGenerator"

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBBlenderGenerator?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let node = HKBNodeHeader.decode(&cursor)
        return HKBBlenderGenerator(
            node: node,
            blender: HKBBlenderFields.decode(&cursor),
            unresolved: cursor.unresolved
        )
    }

    public var nodeName: String? {
        node.name
    }

    public var references: [HKBReference] {
        node.references + blender.references
    }

    public var summary: String {
        blender.summary
    }
}

/// Decoded `hkbBlenderGeneratorChild`, size 80. Derives `hkbBindable`, so it
/// has no name of its own — a child is identified by its index in the parent.
nonisolated public struct HKBBlenderGeneratorChild: HKBClass, Equatable, Sendable {
    public let variableBindingSet: HKXPointerTarget?
    public let generator: HKXPointerTarget?
    /// Optional per-bone mask restricting where this child contributes.
    public let boneWeights: HKXPointerTarget?
    /// This child's share of the blend, or its position along the parent's
    /// blend parameter when the parent is a parametric blender.
    public let weight: Float
    /// Separate weight for the root (world-from-model) transform, so a child
    /// can drive motion without driving the pose.
    public let worldFromModelWeight: Float
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbBlenderGeneratorChild"

    private static let variableBindingSetField = HKXField(0x10, "m_variableBindingSet")
    private static let generatorField = HKXField(0x30, "m_generator")
    private static let boneWeightsField = HKXField(0x38, "m_boneWeights")
    private static let weightField = HKXField(0x40, "m_weight")
    private static let worldFromModelWeightField = HKXField(
        0x44, "m_worldFromModelWeight"
    )

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBBlenderGeneratorChild?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        return HKBBlenderGeneratorChild(
            variableBindingSet: cursor.pointer(at: variableBindingSetField),
            generator: cursor.pointer(at: generatorField),
            boneWeights: cursor.pointer(at: boneWeightsField),
            weight: cursor.float32(at: weightField) ?? 0,
            worldFromModelWeight: cursor.float32(at: worldFromModelWeightField) ?? 0,
            unresolved: cursor.unresolved
        )
    }

    public var references: [HKBReference] {
        HKBReference.optional("m_variableBindingSet", variableBindingSet)
            + HKBReference.optional("m_generator", generator)
            + HKBReference.optional("m_boneWeights", boneWeights)
    }

    public var summary: String {
        "weight \(weight), world-from-model weight \(worldFromModelWeight)"
    }
}

/// Decoded `hkbPoseMatchingGenerator`, size 240. Derives `hkbBlenderGenerator`,
/// so the blender members come first and its own start at 0xA0. Used where a
/// switch between children must land on a matching pose rather than cut.
nonisolated public struct HKBPoseMatchingGenerator: HKBClass, Equatable, Sendable {
    public let node: HKBNodeHeader
    public let blender: HKBBlenderFields
    public let worldFromModelRotation: SIMD4<Float>
    public let blendSpeed: Float
    public let minSpeedToSwitch: Float
    public let minSwitchTimeNoError: Float
    public let minSwitchTimeFullError: Float
    public let startPlayingEventId: Int
    public let startMatchingEventId: Int
    public let rootBoneIndex: Int
    public let otherBoneIndex: Int
    public let anotherBoneIndex: Int
    public let pelvisIndex: Int
    /// `hkbPoseMatchingGenerator::Mode`: 0 match, 1 play, 2 count.
    public let mode: Int
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbPoseMatchingGenerator"

    private static let rotationField = HKXField(0xA0, "m_worldFromModelRotation")
    private static let blendSpeedField = HKXField(0xB0, "m_blendSpeed")
    private static let minSpeedToSwitchField = HKXField(0xB4, "m_minSpeedToSwitch")
    private static let noErrorField = HKXField(0xB8, "m_minSwitchTimeNoError")
    private static let fullErrorField = HKXField(0xBC, "m_minSwitchTimeFullError")
    private static let startPlayingField = HKXField(0xC0, "m_startPlayingEventId")
    private static let startMatchingField = HKXField(0xC4, "m_startMatchingEventId")
    private static let rootBoneField = HKXField(0xC8, "m_rootBoneIndex")
    private static let otherBoneField = HKXField(0xCA, "m_otherBoneIndex")
    private static let anotherBoneField = HKXField(0xCC, "m_anotherBoneIndex")
    private static let pelvisField = HKXField(0xCE, "m_pelvisIndex")
    private static let modeField = HKXField(0xD0, "m_mode")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBPoseMatchingGenerator?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let node = HKBNodeHeader.decode(&cursor)
        let blender = HKBBlenderFields.decode(&cursor)
        return HKBPoseMatchingGenerator(
            node: node,
            blender: blender,
            worldFromModelRotation: cursor.vector4(at: rotationField) ?? SIMD4(),
            blendSpeed: cursor.float32(at: blendSpeedField) ?? 0,
            minSpeedToSwitch: cursor.float32(at: minSpeedToSwitchField) ?? 0,
            minSwitchTimeNoError: cursor.float32(at: noErrorField) ?? 0,
            minSwitchTimeFullError: cursor.float32(at: fullErrorField) ?? 0,
            startPlayingEventId: cursor.int32(at: startPlayingField) ?? -1,
            startMatchingEventId: cursor.int32(at: startMatchingField) ?? -1,
            rootBoneIndex: cursor.int16(at: rootBoneField) ?? -1,
            otherBoneIndex: cursor.int16(at: otherBoneField) ?? -1,
            anotherBoneIndex: cursor.int16(at: anotherBoneField) ?? -1,
            pelvisIndex: cursor.int16(at: pelvisField) ?? -1,
            mode: cursor.int8(at: modeField) ?? 0,
            unresolved: cursor.unresolved
        )
    }

    public var nodeName: String? {
        node.name
    }

    public var references: [HKBReference] {
        node.references + blender.references
    }

    public var summary: String {
        blender.summary + ", pose matching mode \(mode), pelvis bone \(pelvisIndex)"
    }
}
