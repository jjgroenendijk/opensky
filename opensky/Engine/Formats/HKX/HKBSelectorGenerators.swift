// The remaining stock Havok generator classes (todo 14.2): the selector and
// wrapper generators that pick or decorate one child, the behavior reference
// that names another file, and `hkbBlendingTransitionEffect`, the transition
// class every state-machine transition in the vanilla player graph uses.
//
// 64-bit member offsets from ret2end/HKX2Library (MIT); signatures match the
// local SSE files (hkbManualSelectorGenerator 0xD932FAB8, hkbModifierGenerator
// 0x1F81FAE6, hkbBehaviorReferenceGenerator 0x0FCB5423,
// hkbBlendingTransitionEffect 0xFD8584FE). No Havok SDK or Bethesda code
// consulted (AGENTS.md Legal & IP). Byte map:
// docs/formats/hkx-behavior-nodes.md.

import Foundation

/// Decoded `hkbManualSelectorGenerator`, size 96: runs exactly one of its
/// children, chosen by an index that is normally bound to a graph variable.
nonisolated struct HKBManualSelectorGenerator: HKBClass, Equatable {
    let node: HKBNodeHeader
    let generators: [HKXPointerTarget?]
    /// Index into `m_generators`; the member a binding writes to select a child.
    let selectedGeneratorIndex: Int
    /// The index actually running. Authored as a serialized member here rather
    /// than `SERIALIZE_IGNORED`, so it is decoded even though 14.3 owns it.
    let currentGeneratorIndex: Int
    let unresolved: [HKXUnresolvedReference]

    static let className = "hkbManualSelectorGenerator"

    private static let generatorsField = HKXField(0x48, "m_generators")
    private static let selectedField = HKXField(0x58, "m_selectedGeneratorIndex")
    private static let currentField = HKXField(0x59, "m_currentGeneratorIndex")

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBManualSelectorGenerator?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let node = HKBNodeHeader.decode(&cursor)
        return HKBManualSelectorGenerator(
            node: node,
            generators: cursor.pointerArray(at: generatorsField),
            selectedGeneratorIndex: cursor.int8(at: selectedField) ?? -1,
            currentGeneratorIndex: cursor.int8(at: currentField) ?? -1,
            unresolved: cursor.unresolved
        )
    }

    var nodeName: String? {
        node.name
    }

    var references: [HKBReference] {
        node.references + HKBReference.each("m_generators", generators)
    }

    var summary: String {
        "\(generators.count) generators, selected \(selectedGeneratorIndex)"
    }
}

/// Decoded `hkbModifierGenerator`, size 88: runs one child generator and pipes
/// its pose through one modifier.
nonisolated struct HKBModifierGenerator: HKBClass, Equatable {
    let node: HKBNodeHeader
    let modifier: HKXPointerTarget?
    let generator: HKXPointerTarget?
    let unresolved: [HKXUnresolvedReference]

    static let className = "hkbModifierGenerator"

    private static let modifierField = HKXField(0x48, "m_modifier")
    private static let generatorField = HKXField(0x50, "m_generator")

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBModifierGenerator?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let node = HKBNodeHeader.decode(&cursor)
        return HKBModifierGenerator(
            node: node,
            modifier: cursor.pointer(at: modifierField),
            generator: cursor.pointer(at: generatorField),
            unresolved: cursor.unresolved
        )
    }

    var nodeName: String? {
        node.name
    }

    var references: [HKBReference] {
        node.references
            + HKBReference.optional("m_modifier", modifier)
            + HKBReference.optional("m_generator", generator)
    }

    var summary: String {
        "modifier \(modifier != nil ? "set" : "none"), "
            + "generator \(generator != nil ? "set" : "none")"
    }
}

/// Decoded `hkbBehaviorReferenceGenerator`, size 88: stands in for the root
/// generator of another behavior file, named rather than pointed at. This is
/// how `0_Master.hkb` pulls in the per-activity behavior files; resolving the
/// name to a loaded graph is item 14.5's job, not this decoder's.
nonisolated struct HKBBehaviorReferenceGenerator: HKBClass, Equatable {
    let node: HKBNodeHeader
    /// Behavior file name as the project's `m_behaviorFilenames` spells it.
    let behaviorName: String?
    let unresolved: [HKXUnresolvedReference]

    static let className = "hkbBehaviorReferenceGenerator"

    private static let behaviorNameField = HKXField(0x48, "m_behaviorName")

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBBehaviorReferenceGenerator?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let node = HKBNodeHeader.decode(&cursor)
        return HKBBehaviorReferenceGenerator(
            node: node,
            behaviorName: cursor.string(at: behaviorNameField),
            unresolved: cursor.unresolved
        )
    }

    var nodeName: String? {
        node.name
    }

    var references: [HKBReference] {
        node.references
    }

    var summary: String {
        "behavior \"\(behaviorName ?? "<none>")\""
    }
}

/// Decoded `hkbBlendingTransitionEffect`, size 144. Derives `hkbTransitionEffect`
/// -> `hkbGenerator`, so `m_selfTransitionMode` and `m_eventMode` at 0x48 and
/// 0x49 come from the base and this class's own members start at 0x50.
nonisolated struct HKBBlendingTransitionEffect: HKBClass, Equatable {
    let node: HKBNodeHeader
    /// `hkbTransitionEffect::SelfTransitionMode`: what happens when a state
    /// transitions to itself (0 continue, 1 reset, 2 blend).
    let selfTransitionMode: Int
    /// `hkbTransitionEffect::EventMode`: whether events fire during the blend.
    let eventMode: Int
    /// Blend length in seconds.
    let duration: Float
    /// Where in the destination clip the blend starts, as a fraction.
    let toGeneratorStartTimeFraction: Float
    /// `hkbBlendingTransitionEffect::FlagBits`, a bit set (1 ignore
    /// from-generator, 2 sync, 4 ignore world-from-model, 8 ignore to-generator).
    let flags: Int
    /// `hkbBlendingTransitionEffect::EndMode`: what to do when the source clip
    /// ends before the blend does.
    let endMode: Int
    /// `hkbBlendCurveUtils::BlendCurve`: 0 smooth, 1 linear, 2 linear-to-ease,
    /// 3 ease-to-linear.
    let blendCurve: Int
    let unresolved: [HKXUnresolvedReference]

    static let className = "hkbBlendingTransitionEffect"

    private static let selfTransitionModeField = HKXField(0x48, "m_selfTransitionMode")
    private static let eventModeField = HKXField(0x49, "m_eventMode")
    private static let durationField = HKXField(0x50, "m_duration")
    private static let startFractionField = HKXField(
        0x54, "m_toGeneratorStartTimeFraction"
    )
    private static let flagsField = HKXField(0x58, "m_flags")
    private static let endModeField = HKXField(0x5A, "m_endMode")
    private static let blendCurveField = HKXField(0x5B, "m_blendCurve")

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBBlendingTransitionEffect?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let node = HKBNodeHeader.decode(&cursor)
        return HKBBlendingTransitionEffect(
            node: node,
            selfTransitionMode: cursor.int8(at: selfTransitionModeField) ?? 0,
            eventMode: cursor.int8(at: eventModeField) ?? 0,
            duration: cursor.float32(at: durationField) ?? 0,
            toGeneratorStartTimeFraction: cursor.float32(at: startFractionField) ?? 0,
            flags: cursor.uint16(at: flagsField) ?? 0,
            endMode: cursor.int8(at: endModeField) ?? 0,
            blendCurve: cursor.int8(at: blendCurveField) ?? 0,
            unresolved: cursor.unresolved
        )
    }

    var nodeName: String? {
        node.name
    }

    var references: [HKBReference] {
        node.references
    }

    var summary: String {
        "duration \(duration)s, blend curve \(blendCurve), end mode \(endMode)"
    }
}
