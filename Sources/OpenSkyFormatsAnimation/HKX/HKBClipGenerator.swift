// `hkbClipGenerator` and its trigger array: the leaf of the node tree and the
// only class that names an animation. `m_animationName` is spelled as in the
// character file's `m_animationNames`; `m_animationBindingIndex` indexes it.
// Byte map: docs/formats/hkx-behavior-nodes.md.

import Foundation

/// Decoded `hkbClipGenerator`, size 272. Derives `hkbGenerator` -> `hkbNode`.
nonisolated public struct HKBClipGenerator: HKBClass, Equatable, Sendable {
    public let node: HKBNodeHeader
    /// The clip this generator plays, named as the character file spells it.
    public let animationName: String?
    /// `hkbClipTriggerArray` of events raised at points inside the clip.
    public let triggers: HKXPointerTarget?
    public let cropStartAmountLocalTime: Float
    public let cropEndAmountLocalTime: Float
    public let startTime: Float
    public let playbackSpeed: Float
    /// When positive, the clip is time-scaled to exactly this many seconds.
    public let enforcedDuration: Float
    /// Playback position when `m_mode` is the user-controlled one, as a
    /// fraction of the clip.
    public let userControlledTimeFraction: Float
    /// Index into the character file's animation list; -1 when unbound.
    public let animationBindingIndex: Int
    /// `hkbClipGenerator::PlaybackMode`: 0 single play, 1 loop, 2 user
    /// controlled, 3 ping pong, 4 count.
    public let mode: Int
    /// `hkbClipGenerator::ClipFlags`, a bit set (1 continue motion at end,
    /// 2 sync half cycle in ping pong, 4 mirror, 8 force density).
    public let flags: Int
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbClipGenerator"

    private static let animationNameField = HKXField(0x48, "m_animationName")
    private static let triggersField = HKXField(0x50, "m_triggers")
    private static let cropStartField = HKXField(0x58, "m_cropStartAmountLocalTime")
    private static let cropEndField = HKXField(0x5C, "m_cropEndAmountLocalTime")
    private static let startTimeField = HKXField(0x60, "m_startTime")
    private static let playbackSpeedField = HKXField(0x64, "m_playbackSpeed")
    private static let enforcedDurationField = HKXField(0x68, "m_enforcedDuration")
    private static let userControlledField = HKXField(
        0x6C, "m_userControlledTimeFraction"
    )
    private static let bindingIndexField = HKXField(0x70, "m_animationBindingIndex")
    private static let modeField = HKXField(0x72, "m_mode")
    private static let flagsField = HKXField(0x73, "m_flags")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBClipGenerator?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let node = HKBNodeHeader.decode(&cursor)
        return HKBClipGenerator(
            node: node,
            animationName: cursor.string(at: animationNameField),
            triggers: cursor.pointer(at: triggersField),
            cropStartAmountLocalTime: cursor.float32(at: cropStartField) ?? 0,
            cropEndAmountLocalTime: cursor.float32(at: cropEndField) ?? 0,
            startTime: cursor.float32(at: startTimeField) ?? 0,
            playbackSpeed: cursor.float32(at: playbackSpeedField) ?? 0,
            enforcedDuration: cursor.float32(at: enforcedDurationField) ?? 0,
            userControlledTimeFraction: cursor.float32(at: userControlledField) ?? 0,
            animationBindingIndex: cursor.int16(at: bindingIndexField) ?? -1,
            mode: cursor.int8(at: modeField) ?? 0,
            flags: cursor.int8(at: flagsField) ?? 0,
            unresolved: cursor.unresolved
        )
    }

    public var nodeName: String? {
        node.name
    }

    public var references: [HKBReference] {
        node.references + HKBReference.optional("m_triggers", triggers)
    }

    public var summary: String {
        "clip \"\(animationName ?? "<none>")\", binding \(animationBindingIndex), "
            + "mode \(mode), speed \(playbackSpeed)"
    }
}

/// One entry of `hkbClipTriggerArray::m_triggers`, 32 bytes: an event raised
/// when playback passes a point in the clip.
nonisolated public struct HKBClipTrigger: Equatable, Sendable {
    public let localTime: Float
    public let event: HKBEventProperty
    /// When true `m_localTime` is measured back from the end of the clip.
    public let relativeToEndOfClip: Bool
    /// When true the trigger fires once rather than on every loop.
    public let acyclic: Bool
    /// True when the trigger came from an animation annotation track rather
    /// than from authored behavior data.
    public let isAnnotation: Bool

    public static let stride = 32

    public static func decode(_ element: inout HKXObjectCursor, index: Int) -> HKBClipTrigger {
        let member = "m_triggers[\(index)]"
        return HKBClipTrigger(
            localTime: element
                .float32(at: HKXField(0x00, "\(member).m_localTime")) ?? 0,
            event: HKBEventProperty.decode(&element, at: 0x08, named: "\(member).m_event"),
            relativeToEndOfClip: element
                .bool(at: HKXField(0x18, "\(member).m_relativeToEndOfClip")) ?? false,
            acyclic: element.bool(at: HKXField(0x19, "\(member).m_acyclic")) ?? false,
            isAnnotation: element
                .bool(at: HKXField(0x1A, "\(member).m_isAnnotation")) ?? false
        )
    }
}

/// Decoded `hkbClipTriggerArray`, size 32.
nonisolated public struct HKBClipTriggerArray: HKBClass, Equatable, Sendable {
    public let triggers: [HKBClipTrigger]
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbClipTriggerArray"

    private static let triggersField = HKXField(0x10, "m_triggers")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBClipTriggerArray?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        var triggers: [HKBClipTrigger] = []
        if let view = cursor.array(at: triggersField) {
            triggers.reserveCapacity(view.count)
            for index in 0 ..< view.count {
                guard
                    var element = graph.element(
                        of: view, index: index, stride: HKBClipTrigger.stride
                    )
                else {
                    cursor.recordMiss(triggersField, .outOfBounds)
                    continue
                }
                triggers.append(HKBClipTrigger.decode(&element, index: index))
                cursor.absorb(element)
            }
        }
        return HKBClipTriggerArray(triggers: triggers, unresolved: cursor.unresolved)
    }

    public var references: [HKBReference] {
        triggers.enumerated().flatMap { index, trigger in
            trigger.event.references(named: "m_triggers[\(index)].m_event")
        }
    }

    public var summary: String {
        "\(triggers.count) clip triggers"
    }
}
