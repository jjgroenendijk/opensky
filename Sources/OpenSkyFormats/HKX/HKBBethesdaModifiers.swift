// Bethesda's own modifier classes (todo 14.2), part one: the small ones that
// test node activity, raise events on edges, interpolate a value, and sample
// speed. `BSSpeedSamplerModifier` in particular is what turns the player's
// movement input into the `Speed` variable the locomotion blenders weight
// against, so it is load-bearing for item 14.5 despite being four floats.
//
// 64-bit member offsets from ret2end/HKX2Library (MIT); signatures match the
// local SSE files (BSIsActiveModifier 0xB0FDE45A, BSEventEveryNEventsModifier
// 0x6030970C, BSEventOnDeactivateModifier 0x1062D993,
// BSEventOnFalseToTrueModifier 0x81D0777A, BSInterpValueModifier 0x29ADC802,
// BSModifyOnceModifier 0x1E20A97A, BSSpeedSamplerModifier 0xD297FDA9,
// BSRagdollContactListenerModifier 0x8003D8CE). No Havok SDK, Creation Kit, or
// SKSE internals consulted (AGENTS.md Legal & IP). Byte map:
// docs/formats/hkx-behavior-modifiers.md.

import Foundation

/// Decoded `BSIsActiveModifier`, size 96: publishes whether each of up to five
/// tracked slots is active, optionally inverted. Bound to graph variables, this
/// is how one branch of the graph tests whether another branch is running.
nonisolated public struct BSIsActiveModifier: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    /// Five (isActive, invertActive) pairs in slot order.
    public let isActive: [Bool]
    public let invertActive: [Bool]
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "BSIsActiveModifier"

    /// Ten consecutive bools from 0x50: slot n is at 0x50 + 2n, its invert
    /// flag at 0x51 + 2n.
    private static let slotCount = 5
    private static let slotsOffset = 0x50

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> BSIsActiveModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        var active: [Bool] = []
        var inverted: [Bool] = []
        for slot in 0 ..< slotCount {
            let base = slotsOffset + slot * 2
            active.append(
                cursor.bool(at: HKXField(base, "m_bIsActive\(slot)")) ?? false
            )
            inverted.append(
                cursor.bool(at: HKXField(base + 1, "m_bInvertActive\(slot)")) ?? false
            )
        }
        return BSIsActiveModifier(
            modifier: header,
            isActive: active,
            invertActive: inverted,
            unresolved: cursor.unresolved
        )
    }

    public var nodeName: String? {
        modifier.name
    }

    public var references: [HKBReference] {
        modifier.references
    }

    public var summary: String {
        "active slots " + isActive.map { $0 ? "1" : "0" }.joined()
    }
}

/// Decoded `BSEventEveryNEventsModifier`, size 128: counts one event and raises
/// another every N occurrences, optionally with the count randomised.
nonisolated public struct BSEventEveryNEventsModifier: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    public let eventToCheckFor: HKBEventProperty
    public let eventToSend: HKBEventProperty
    public let numberOfEventsBeforeSend: Int
    public let minimumNumberOfEventsBeforeSend: Int
    public let randomizeNumberOfEvents: Bool
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "BSEventEveryNEventsModifier"

    private static let checkForOffset = 0x50
    private static let toSendOffset = 0x60
    private static let countField = HKXField(0x70, "m_numberOfEventsBeforeSend")
    private static let minimumField = HKXField(
        0x71, "m_minimumNumberOfEventsBeforeSend"
    )
    private static let randomizeField = HKXField(0x72, "m_randomizeNumberOfEvents")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> BSEventEveryNEventsModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        let checkFor = HKBEventProperty.decode(
            &cursor, at: checkForOffset, named: "m_eventToCheckFor"
        )
        let toSend = HKBEventProperty.decode(
            &cursor, at: toSendOffset, named: "m_eventToSend"
        )
        return BSEventEveryNEventsModifier(
            modifier: header,
            eventToCheckFor: checkFor,
            eventToSend: toSend,
            numberOfEventsBeforeSend: cursor.int8(at: countField) ?? 0,
            minimumNumberOfEventsBeforeSend: cursor.int8(at: minimumField) ?? 0,
            randomizeNumberOfEvents: cursor.bool(at: randomizeField) ?? false,
            unresolved: cursor.unresolved
        )
    }

    public var nodeName: String? {
        modifier.name
    }

    public var references: [HKBReference] {
        modifier.references
            + eventToCheckFor.references(named: "m_eventToCheckFor")
            + eventToSend.references(named: "m_eventToSend")
    }

    public var summary: String {
        "event \(eventToSend.id) every \(numberOfEventsBeforeSend) "
            + "of event \(eventToCheckFor.id)"
    }
}

/// Decoded `BSEventOnDeactivateModifier`, size 96: raises one event when the
/// node it sits under is deactivated.
nonisolated public struct BSEventOnDeactivateModifier: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    public let event: HKBEventProperty
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "BSEventOnDeactivateModifier"

    private static let eventOffset = 0x50

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> BSEventOnDeactivateModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        return BSEventOnDeactivateModifier(
            modifier: header,
            event: HKBEventProperty.decode(&cursor, at: eventOffset, named: "m_event"),
            unresolved: cursor.unresolved
        )
    }

    public var nodeName: String? {
        modifier.name
    }

    public var references: [HKBReference] {
        modifier.references + event.references(named: "m_event")
    }

    public var summary: String {
        "raises event \(event.id) on deactivate"
    }
}

/// One of `BSEventOnFalseToTrueModifier`'s three slots: a bound bool, an enable
/// flag, and the event raised when the bool goes false to true.
nonisolated public struct BSFalseToTrueSlot: Equatable, Sendable {
    public let enableEvent: Bool
    public let variableToTest: Bool
    public let eventToSend: HKBEventProperty
}

/// Decoded `BSEventOnFalseToTrueModifier`, size 160: three edge detectors in
/// one node. The slots are laid out at a 24-byte pitch from 0x50.
nonisolated public struct BSEventOnFalseToTrueModifier: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    public let slots: [BSFalseToTrueSlot]
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "BSEventOnFalseToTrueModifier"

    private static let slotCount = 3
    private static let firstSlotOffset = 0x50
    private static let slotPitch = 0x18
    /// The event property sits 8 bytes past the slot's two flags.
    private static let slotEventOffset = 0x08

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> BSEventOnFalseToTrueModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        var slots: [BSFalseToTrueSlot] = []
        for slot in 0 ..< slotCount {
            let base = firstSlotOffset + slot * slotPitch
            // Havok numbers these members from one, not from zero.
            let label = slot + 1
            let enable = cursor
                .bool(at: HKXField(base, "m_bEnableEvent\(label)")) ?? false
            let variable = cursor
                .bool(at: HKXField(base + 1, "m_bVariableToTest\(label)")) ?? false
            let event = HKBEventProperty.decode(
                &cursor, at: base + slotEventOffset, named: "m_EventToSend\(label)"
            )
            slots.append(BSFalseToTrueSlot(
                enableEvent: enable, variableToTest: variable, eventToSend: event
            ))
        }
        return BSEventOnFalseToTrueModifier(
            modifier: header, slots: slots, unresolved: cursor.unresolved
        )
    }

    public var nodeName: String? {
        modifier.name
    }

    public var references: [HKBReference] {
        modifier.references + slots.enumerated().flatMap { index, slot in
            slot.eventToSend.references(named: "m_EventToSend\(index + 1)")
        }
    }

    public var summary: String {
        "slots " + slots.map { "\($0.enableEvent ? "on" : "off"):\($0.eventToSend.id)" }
            .joined(separator: " ")
    }
}

/// Decoded `BSInterpValueModifier`, size 104: eases `m_result` from `m_source`
/// towards `m_target` at `m_gain` per second. All four are normally bound.
nonisolated public struct BSInterpValueModifier: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    public let source: Float
    public let target: Float
    public let result: Float
    public let gain: Float
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "BSInterpValueModifier"

    private static let sourceField = HKXField(0x50, "m_source")
    private static let targetField = HKXField(0x54, "m_target")
    private static let resultField = HKXField(0x58, "m_result")
    private static let gainField = HKXField(0x5C, "m_gain")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> BSInterpValueModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        return BSInterpValueModifier(
            modifier: header,
            source: cursor.float32(at: sourceField) ?? 0,
            target: cursor.float32(at: targetField) ?? 0,
            result: cursor.float32(at: resultField) ?? 0,
            gain: cursor.float32(at: gainField) ?? 0,
            unresolved: cursor.unresolved
        )
    }

    public var nodeName: String? {
        modifier.name
    }

    public var references: [HKBReference] {
        modifier.references
    }

    public var summary: String {
        "interpolate \(source) -> \(target) at gain \(gain)"
    }
}

/// Decoded `BSModifyOnceModifier`, size 112: runs one modifier on activation and
/// another on deactivation, each exactly once.
nonisolated public struct BSModifyOnceModifier: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    public let onActivateModifier: HKXPointerTarget?
    public let onDeactivateModifier: HKXPointerTarget?
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "BSModifyOnceModifier"

    private static let onActivateField = HKXField(0x50, "m_pOnActivateModifier")
    private static let onDeactivateField = HKXField(0x60, "m_pOnDeactivateModifier")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> BSModifyOnceModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        return BSModifyOnceModifier(
            modifier: header,
            onActivateModifier: cursor.pointer(at: onActivateField),
            onDeactivateModifier: cursor.pointer(at: onDeactivateField),
            unresolved: cursor.unresolved
        )
    }

    public var nodeName: String? {
        modifier.name
    }

    public var references: [HKBReference] {
        modifier.references
            + HKBReference.optional("m_pOnActivateModifier", onActivateModifier)
            + HKBReference.optional("m_pOnDeactivateModifier", onDeactivateModifier)
    }

    public var summary: String {
        "on activate \(onActivateModifier != nil ? "set" : "none"), "
            + "on deactivate \(onDeactivateModifier != nil ? "set" : "none")"
    }
}

/// Decoded `BSSpeedSamplerModifier`, size 96: samples the character's movement
/// and publishes a speed and a direction the locomotion blenders weight against.
nonisolated public struct BSSpeedSamplerModifier: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    public let state: Int
    public let direction: Float
    public let goalSpeed: Float
    public let speedOut: Float
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "BSSpeedSamplerModifier"

    private static let stateField = HKXField(0x50, "m_state")
    private static let directionField = HKXField(0x54, "m_direction")
    private static let goalSpeedField = HKXField(0x58, "m_goalSpeed")
    private static let speedOutField = HKXField(0x5C, "m_speedOut")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> BSSpeedSamplerModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        return BSSpeedSamplerModifier(
            modifier: header,
            state: cursor.int32(at: stateField) ?? 0,
            direction: cursor.float32(at: directionField) ?? 0,
            goalSpeed: cursor.float32(at: goalSpeedField) ?? 0,
            speedOut: cursor.float32(at: speedOutField) ?? 0,
            unresolved: cursor.unresolved
        )
    }

    public var nodeName: String? {
        modifier.name
    }

    public var references: [HKBReference] {
        modifier.references
    }

    public var summary: String {
        "state \(state), goal speed \(goalSpeed)"
    }
}

/// Decoded `BSRagdollContactListenerModifier`, size 136: raises an event when a
/// listed ragdoll bone touches something.
nonisolated public struct BSRagdollContactListenerModifier: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    public let contactEvent: HKBEventProperty
    /// `hkbBoneIndexArray` of the bones listened to.
    public let bones: HKXPointerTarget?
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "BSRagdollContactListenerModifier"

    private static let contactEventOffset = 0x58
    private static let bonesField = HKXField(0x68, "m_bones")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> BSRagdollContactListenerModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        let event = HKBEventProperty.decode(
            &cursor, at: contactEventOffset, named: "m_contactEvent"
        )
        return BSRagdollContactListenerModifier(
            modifier: header,
            contactEvent: event,
            bones: cursor.pointer(at: bonesField),
            unresolved: cursor.unresolved
        )
    }

    public var nodeName: String? {
        modifier.name
    }

    public var references: [HKBReference] {
        modifier.references
            + contactEvent.references(named: "m_contactEvent")
            + HKBReference.optional("m_bones", bones)
    }

    public var summary: String {
        "contact raises event \(contactEvent.id)"
    }
}
