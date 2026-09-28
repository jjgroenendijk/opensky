// Bethesda's own generator classes (todo 14.2). The census counts twelve `BS*`
// classes across the vanilla player behavior files, so a decoder set covering
// only stock Havok classes would miss part of the graph outright — 435
// `BSSynchronizedClipGenerator` objects alone. They register in the packfile
// exactly like stock classes and derive from the stock bases, so they decode
// through the same helpers.
//
// 64-bit member offsets from ret2end/HKX2Library (MIT), which carries the
// Bethesda extensions alongside the stock classes; signatures match the local
// SSE files (BSSynchronizedClipGenerator 0xD83BEA64, BSiStateTaggingGenerator
// 0xF0826FC1, BSBoneSwitchGenerator 0xF33D3EEA, BSBoneSwitchGeneratorBoneData
// 0xC1215BE6, BSCyclicBlendTransitionGenerator 0x5119EB06,
// BSOffsetAnimationGenerator 0xB8571122). No Havok SDK, Creation Kit, or SKSE
// internals consulted (AGENTS.md Legal & IP). Byte map:
// docs/formats/hkx-behavior-modifiers.md.

import Foundation

/// Decoded `BSSynchronizedClipGenerator`, size 304: wraps a clip generator so
/// two characters can play matching halves of a paired animation, lining them
/// up on a marker rather than on clip time. Used by the killmove and furniture
/// states.
nonisolated package struct BSSynchronizedClipGenerator: HKBClass, Equatable {
    package let node: HKBNodeHeader
    /// The wrapped `hkbClipGenerator`.
    package let clipGenerator: HKXPointerTarget?
    /// Prefix prepended to the partner's animation name to find its half.
    package let syncAnimPrefix: String?
    package let syncClipIgnoreMarkPlacement: Bool
    package let getToMarkTime: Float
    package let markErrorThreshold: Float
    /// True on the character the pair is aligned to.
    package let leadCharacter: Bool
    package let reorientSupportChar: Bool
    package let applyMotionFromRoot: Bool
    /// Index into the character file's animation list; -1 when unbound.
    package let animationBindingIndex: Int
    package let unresolved: [HKXUnresolvedReference]

    package static let className = "BSSynchronizedClipGenerator"

    private static let clipGeneratorField = HKXField(0x50, "m_pClipGenerator")
    private static let syncAnimPrefixField = HKXField(0x58, "m_SyncAnimPrefix")
    private static let ignoreMarkField = HKXField(
        0x60, "m_bSyncClipIgnoreMarkPlacement"
    )
    private static let getToMarkTimeField = HKXField(0x64, "m_fGetToMarkTime")
    private static let markErrorField = HKXField(0x68, "m_fMarkErrorThreshold")
    private static let leadCharacterField = HKXField(0x6C, "m_bLeadCharacter")
    private static let reorientField = HKXField(0x6D, "m_bReorientSupportChar")
    private static let applyMotionField = HKXField(0x6E, "m_bApplyMotionFromRoot")
    /// Past three `SERIALIZE_IGNORED` qs-transforms and the runtime pointers.
    private static let bindingIndexField = HKXField(0x128, "m_sAnimationBindingIndex")

    package static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> BSSynchronizedClipGenerator?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let node = HKBNodeHeader.decode(&cursor)
        return BSSynchronizedClipGenerator(
            node: node,
            clipGenerator: cursor.pointer(at: clipGeneratorField),
            syncAnimPrefix: cursor.string(at: syncAnimPrefixField),
            syncClipIgnoreMarkPlacement: cursor.bool(at: ignoreMarkField) ?? false,
            getToMarkTime: cursor.float32(at: getToMarkTimeField) ?? 0,
            markErrorThreshold: cursor.float32(at: markErrorField) ?? 0,
            leadCharacter: cursor.bool(at: leadCharacterField) ?? false,
            reorientSupportChar: cursor.bool(at: reorientField) ?? false,
            applyMotionFromRoot: cursor.bool(at: applyMotionField) ?? false,
            animationBindingIndex: cursor.int16(at: bindingIndexField) ?? -1,
            unresolved: cursor.unresolved
        )
    }

    package var nodeName: String? {
        node.name
    }

    package var references: [HKBReference] {
        node.references + HKBReference.optional("m_pClipGenerator", clipGenerator)
    }

    package var summary: String {
        "sync prefix \"\(syncAnimPrefix ?? "")\", lead \(leadCharacter), "
            + "binding \(animationBindingIndex)"
    }
}

/// Decoded `BSiStateTaggingGenerator`, size 96: runs one child and, while it
/// runs, publishes a state number the rest of the graph can test.
nonisolated package struct BSiStateTaggingGenerator: HKBClass, Equatable {
    package let node: HKBNodeHeader
    package let defaultGenerator: HKXPointerTarget?
    package let stateToSetAs: Int
    package let priority: Int
    package let unresolved: [HKXUnresolvedReference]

    package static let className = "BSiStateTaggingGenerator"

    private static let defaultGeneratorField = HKXField(0x50, "m_pDefaultGenerator")
    private static let stateToSetAsField = HKXField(0x58, "m_iStateToSetAs")
    private static let priorityField = HKXField(0x5C, "m_iPriority")

    package static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> BSiStateTaggingGenerator?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let node = HKBNodeHeader.decode(&cursor)
        return BSiStateTaggingGenerator(
            node: node,
            defaultGenerator: cursor.pointer(at: defaultGeneratorField),
            stateToSetAs: cursor.int32(at: stateToSetAsField) ?? -1,
            priority: cursor.int32(at: priorityField) ?? 0,
            unresolved: cursor.unresolved
        )
    }

    package var nodeName: String? {
        node.name
    }

    package var references: [HKBReference] {
        node.references + HKBReference.optional("m_pDefaultGenerator", defaultGenerator)
    }

    package var summary: String {
        "tags state \(stateToSetAs) at priority \(priority)"
    }
}

/// Decoded `BSBoneSwitchGeneratorBoneData`, size 64: one child of a bone-switch
/// generator plus the bone mask it owns. Derives `hkbBindable`, so it has no
/// name.
nonisolated package struct BSBoneSwitchGeneratorBoneData: HKBClass, Equatable {
    package let variableBindingSet: HKXPointerTarget?
    package let generator: HKXPointerTarget?
    /// `hkbBoneWeightArray` selecting the bones this child owns.
    package let boneWeight: HKXPointerTarget?
    package let unresolved: [HKXUnresolvedReference]

    package static let className = "BSBoneSwitchGeneratorBoneData"

    private static let variableBindingSetField = HKXField(0x10, "m_variableBindingSet")
    private static let generatorField = HKXField(0x30, "m_pGenerator")
    private static let boneWeightField = HKXField(0x38, "m_spBoneWeight")

    package static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> BSBoneSwitchGeneratorBoneData?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        return BSBoneSwitchGeneratorBoneData(
            variableBindingSet: cursor.pointer(at: variableBindingSetField),
            generator: cursor.pointer(at: generatorField),
            boneWeight: cursor.pointer(at: boneWeightField),
            unresolved: cursor.unresolved
        )
    }

    package var references: [HKBReference] {
        HKBReference.optional("m_variableBindingSet", variableBindingSet)
            + HKBReference.optional("m_pGenerator", generator)
            + HKBReference.optional("m_spBoneWeight", boneWeight)
    }

    package var summary: String {
        "bone-switch child, mask \(boneWeight != nil ? "set" : "none")"
    }
}

/// Decoded `BSBoneSwitchGenerator`, size 112: runs a default generator for the
/// whole skeleton and overrides named bone groups with other children. This is
/// how the first-person arms are driven from a different clip than the body.
nonisolated package struct BSBoneSwitchGenerator: HKBClass, Equatable {
    package let node: HKBNodeHeader
    package let defaultGenerator: HKXPointerTarget?
    /// `BSBoneSwitchGeneratorBoneData` objects, index-preserving.
    package let children: [HKXPointerTarget?]
    package let unresolved: [HKXUnresolvedReference]

    package static let className = "BSBoneSwitchGenerator"

    private static let defaultGeneratorField = HKXField(0x50, "m_pDefaultGenerator")
    private static let childrenField = HKXField(0x58, "m_ChildrenA")

    package static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> BSBoneSwitchGenerator?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let node = HKBNodeHeader.decode(&cursor)
        return BSBoneSwitchGenerator(
            node: node,
            defaultGenerator: cursor.pointer(at: defaultGeneratorField),
            children: cursor.pointerArray(at: childrenField),
            unresolved: cursor.unresolved
        )
    }

    package var nodeName: String? {
        node.name
    }

    package var references: [HKBReference] {
        node.references
            + HKBReference.optional("m_pDefaultGenerator", defaultGenerator)
            + HKBReference.each("m_ChildrenA", children)
    }

    package var summary: String {
        "\(children.count) bone-switch children"
    }
}

/// Decoded `BSCyclicBlendTransitionGenerator`, size 176: wraps a blender so a
/// blend parameter can be frozen at a cycle boundary, which keeps a looping
/// clip from popping when the parameter moves mid-stride.
nonisolated package struct BSCyclicBlendTransitionGenerator: HKBClass, Equatable {
    package let node: HKBNodeHeader
    package let blenderGenerator: HKXPointerTarget?
    package let eventToFreezeBlendValue: HKBEventProperty
    package let eventToCrossBlend: HKBEventProperty
    package let blendParameter: Float
    package let transitionDuration: Float
    /// `hkbBlendCurveUtils::BlendCurve`.
    package let blendCurve: Int
    package let unresolved: [HKXUnresolvedReference]

    package static let className = "BSCyclicBlendTransitionGenerator"

    private static let blenderGeneratorField = HKXField(0x50, "m_pBlenderGenerator")
    private static let freezeEventOffset = 0x58
    private static let crossBlendEventOffset = 0x68
    private static let blendParameterField = HKXField(0x78, "m_fBlendParameter")
    private static let transitionDurationField = HKXField(0x7C, "m_fTransitionDuration")
    private static let blendCurveField = HKXField(0x80, "m_eBlendCurve")

    package static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> BSCyclicBlendTransitionGenerator?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let node = HKBNodeHeader.decode(&cursor)
        let generator = cursor.pointer(at: blenderGeneratorField)
        let freeze = HKBEventProperty.decode(
            &cursor, at: freezeEventOffset, named: "m_EventToFreezeBlendValue"
        )
        let cross = HKBEventProperty.decode(
            &cursor, at: crossBlendEventOffset, named: "m_EventToCrossBlend"
        )
        return BSCyclicBlendTransitionGenerator(
            node: node,
            blenderGenerator: generator,
            eventToFreezeBlendValue: freeze,
            eventToCrossBlend: cross,
            blendParameter: cursor.float32(at: blendParameterField) ?? 0,
            transitionDuration: cursor.float32(at: transitionDurationField) ?? 0,
            blendCurve: cursor.int8(at: blendCurveField) ?? 0,
            unresolved: cursor.unresolved
        )
    }

    package var nodeName: String? {
        node.name
    }

    package var references: [HKBReference] {
        node.references
            + HKBReference.optional("m_pBlenderGenerator", blenderGenerator)
            + eventToFreezeBlendValue.references(named: "m_EventToFreezeBlendValue")
            + eventToCrossBlend.references(named: "m_EventToCrossBlend")
    }

    package var summary: String {
        "freeze on event \(eventToFreezeBlendValue.id), "
            + "transition \(transitionDuration)s"
    }
}

/// Decoded `BSOffsetAnimationGenerator`, size 176: adds a pose offset sampled
/// from a second clip on top of a default generator, scaled by a variable.
nonisolated package struct BSOffsetAnimationGenerator: HKBClass, Equatable {
    package let node: HKBNodeHeader
    package let defaultGenerator: HKXPointerTarget?
    package let offsetClipGenerator: HKXPointerTarget?
    /// The blend amount; normally bound to a graph variable.
    package let offsetVariable: Float
    package let offsetRangeStart: Float
    package let offsetRangeEnd: Float
    package let unresolved: [HKXUnresolvedReference]

    package static let className = "BSOffsetAnimationGenerator"

    private static let defaultGeneratorField = HKXField(0x50, "m_pDefaultGenerator")
    private static let offsetClipField = HKXField(0x60, "m_pOffsetClipGenerator")
    private static let offsetVariableField = HKXField(0x68, "m_fOffsetVariable")
    private static let rangeStartField = HKXField(0x6C, "m_fOffsetRangeStart")
    private static let rangeEndField = HKXField(0x70, "m_fOffsetRangeEnd")

    package static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> BSOffsetAnimationGenerator?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let node = HKBNodeHeader.decode(&cursor)
        return BSOffsetAnimationGenerator(
            node: node,
            defaultGenerator: cursor.pointer(at: defaultGeneratorField),
            offsetClipGenerator: cursor.pointer(at: offsetClipField),
            offsetVariable: cursor.float32(at: offsetVariableField) ?? 0,
            offsetRangeStart: cursor.float32(at: rangeStartField) ?? 0,
            offsetRangeEnd: cursor.float32(at: rangeEndField) ?? 0,
            unresolved: cursor.unresolved
        )
    }

    package var nodeName: String? {
        node.name
    }

    package var references: [HKBReference] {
        node.references
            + HKBReference.optional("m_pDefaultGenerator", defaultGenerator)
            + HKBReference.optional("m_pOffsetClipGenerator", offsetClipGenerator)
    }

    package var summary: String {
        "offset range \(offsetRangeStart)-\(offsetRangeEnd)"
    }
}
