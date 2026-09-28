// The blending generators (todo 14.2): `hkbBlenderGenerator`, the
// `hkbBlenderGeneratorChild` records it weights, and `hkbPoseMatchingGenerator`,
// which derives from the blender and adds pose-similarity switching.
//
// A blender runs several child generators at once and mixes their poses. Which
// children are active, and at what weight, is what makes a walk turn into a
// run: `m_blendParameter` is normally bound to a graph variable such as
// `Speed`, and each child's `m_weight` places it along that parameter.
//
// 64-bit member offsets from ret2end/HKX2Library (MIT); signatures match the
// local SSE files (hkbBlenderGenerator 0x22DF7147, hkbBlenderGeneratorChild
// 0xE2B384B0, hkbPoseMatchingGenerator 0x29E271B4). No Havok SDK or Bethesda
// code consulted (AGENTS.md Legal & IP). Byte map:
// docs/formats/hkx-behavior-nodes.md.

import Foundation

/// The members `hkbBlenderGenerator` declares, shared with the subclass
/// `hkbPoseMatchingGenerator` so both read one layout rather than two copies.
nonisolated package struct HKBBlenderFields: Equatable {
    /// Below this weight a child is dropped in favour of the reference pose.
    package let referencePoseWeightThreshold: Float
    /// The value children are weighted against; normally variable-bound.
    package let blendParameter: Float
    package let minCyclicBlendParameter: Float
    package let maxCyclicBlendParameter: Float
    /// Child whose clip time the others follow, or -1 for no sync.
    package let indexOfSyncMasterChild: Int
    /// `hkbBlenderGenerator::BlenderFlags`: bit 0 sync cycles, bit 1 smooth
    /// generator weights, bit 2 parametric blend, bit 3 velocity sync.
    package let flags: Int
    /// When true the last child is subtracted from the blend rather than added.
    package let subtractLastChild: Bool
    /// `hkbBlenderGeneratorChild` objects, index-preserving.
    package let children: [HKXPointerTarget?]

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

    package static func decode(_ cursor: inout HKXObjectCursor) -> HKBBlenderFields {
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

    package var references: [HKBReference] {
        HKBReference.each("m_children", children)
    }

    package var summary: String {
        "\(children.count) children, blend parameter \(blendParameter), flags \(flags)"
    }
}

/// Decoded `hkbBlenderGenerator`, size 160.
nonisolated package struct HKBBlenderGenerator: HKBClass, Equatable {
    package let node: HKBNodeHeader
    package let blender: HKBBlenderFields
    package let unresolved: [HKXUnresolvedReference]

    package static let className = "hkbBlenderGenerator"

    package static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
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

    package var nodeName: String? {
        node.name
    }

    package var references: [HKBReference] {
        node.references + blender.references
    }

    package var summary: String {
        blender.summary
    }
}

/// Decoded `hkbBlenderGeneratorChild`, size 80. Derives `hkbBindable`, so it
/// has no name of its own — a child is identified by its index in the parent.
nonisolated package struct HKBBlenderGeneratorChild: HKBClass, Equatable {
    package let variableBindingSet: HKXPointerTarget?
    package let generator: HKXPointerTarget?
    /// Optional per-bone mask restricting where this child contributes.
    package let boneWeights: HKXPointerTarget?
    /// This child's share of the blend, or its position along the parent's
    /// blend parameter when the parent is a parametric blender.
    package let weight: Float
    /// Separate weight for the root (world-from-model) transform, so a child
    /// can drive motion without driving the pose.
    package let worldFromModelWeight: Float
    package let unresolved: [HKXUnresolvedReference]

    package static let className = "hkbBlenderGeneratorChild"

    private static let variableBindingSetField = HKXField(0x10, "m_variableBindingSet")
    private static let generatorField = HKXField(0x30, "m_generator")
    private static let boneWeightsField = HKXField(0x38, "m_boneWeights")
    private static let weightField = HKXField(0x40, "m_weight")
    private static let worldFromModelWeightField = HKXField(
        0x44, "m_worldFromModelWeight"
    )

    package static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
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

    package var references: [HKBReference] {
        HKBReference.optional("m_variableBindingSet", variableBindingSet)
            + HKBReference.optional("m_generator", generator)
            + HKBReference.optional("m_boneWeights", boneWeights)
    }

    package var summary: String {
        "weight \(weight), world-from-model weight \(worldFromModelWeight)"
    }
}

/// Decoded `hkbPoseMatchingGenerator`, size 240. Derives `hkbBlenderGenerator`,
/// so the blender members come first and its own start at 0xA0. Used where a
/// switch between children must land on a matching pose rather than cut.
nonisolated package struct HKBPoseMatchingGenerator: HKBClass, Equatable {
    package let node: HKBNodeHeader
    package let blender: HKBBlenderFields
    package let worldFromModelRotation: SIMD4<Float>
    package let blendSpeed: Float
    package let minSpeedToSwitch: Float
    package let minSwitchTimeNoError: Float
    package let minSwitchTimeFullError: Float
    package let startPlayingEventId: Int
    package let startMatchingEventId: Int
    package let rootBoneIndex: Int
    package let otherBoneIndex: Int
    package let anotherBoneIndex: Int
    package let pelvisIndex: Int
    /// `hkbPoseMatchingGenerator::Mode`: 0 match, 1 play, 2 count.
    package let mode: Int
    package let unresolved: [HKXUnresolvedReference]

    package static let className = "hkbPoseMatchingGenerator"

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

    package static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
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

    package var nodeName: String? {
        node.name
    }

    package var references: [HKBReference] {
        node.references + blender.references
    }

    package var summary: String {
        blender.summary + ", pose matching mode \(mode), pelvis bone \(pelvisIndex)"
    }
}
