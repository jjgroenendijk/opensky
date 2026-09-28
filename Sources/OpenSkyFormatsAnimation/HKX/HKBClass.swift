// The shape every Havok Behavior node, modifier, and helper class decoder
// shares (todo 14.2), plus the three inherited headers almost all of them
// start with. Item 14.1 built the object graph and the graph-level classes;
// this is the contract the node classes themselves are written against, so the
// 14.3 evaluator and `openskycli hkx` can walk a decoded graph without a
// hand-written switch over class names.
//
// Nothing here evaluates anything. `references` exists so the walk can follow
// the tree generically, and `summary` so a dump can show that a class's own
// fields really decoded rather than that its bytes were merely reachable.
//
// 64-bit member offsets from ret2end/HKX2Library (MIT), whose class signatures
// match the local SSE files (hkbNode 0x6D26F61D, hkbGenerator 0x0D68AEFC,
// hkbModifier 0x96EC5CED, hkbEventBase 0x76BDDB31). No Havok SDK or Bethesda
// code consulted (AGENTS.md Legal & IP). Byte map and citations:
// docs/formats/hkx-behavior-nodes.md.

import Foundation

/// One outgoing pointer of a decoded object: which member holds it and where
/// it lands. The walk follows these; the field name is carried so a dump can
/// say *why* one object references another.
nonisolated public struct HKBReference: Equatable, Sendable {
    public let field: String
    public let target: HKXPointerTarget

    public init(_ field: String, _ target: HKXPointerTarget) {
        self.field = field
        self.target = target
    }

    /// Builds a reference for an optional pointer, dropping the absent case, so
    /// a class can list its members without a guard per member.
    public static func optional(_ field: String, _ target: HKXPointerTarget?) -> [HKBReference] {
        target.map { [HKBReference(field, $0)] } ?? []
    }

    /// Builds references for an index-preserving pointer array, naming each
    /// element by its index so a miss is locatable.
    public static func each(_ field: String, _ targets: [HKXPointerTarget?]) -> [HKBReference] {
        targets.enumerated().compactMap { index, target in
            target.map { HKBReference("\(field)[\(index)]", $0) }
        }
    }
}

/// One decoded Havok class. Implemented by every class in the registry; the
/// registry is what turns a class name from the packfile's virtual-fixup
/// inventory into one of these.
nonisolated public protocol HKBClass: Sendable {
    /// The Havok class name exactly as the packfile's class-name table spells
    /// it, which is also this decoder's registry key.
    static var className: String { get }
    /// `hkbNode::m_name` for the classes that derive from `hkbNode`; nil for
    /// the helper classes (arrays, payloads, conditions) that carry no name.
    var nodeName: String? { get }
    /// Every object this one points at, in member order.
    var references: [HKBReference] { get }
    /// Fields that did not resolve while decoding this object.
    var unresolved: [HKXUnresolvedReference] { get }
    /// One line naming this object's own distinguishing field values, for the
    /// CLI dump and for the sweep report.
    var summary: String { get }
}

nonisolated extension HKBClass {
    public var nodeName: String? {
        nil
    }

    public var references: [HKBReference] {
        []
    }

    /// The instance-side spelling of the class name, so a walk holding an
    /// existential can report what it decoded.
    public var className: String {
        Self.className
    }
}

/// `hkbNode`'s serialized members, inherited by every generator and modifier.
/// `hkbBindable` contributes `m_variableBindingSet` at 0x10; the rest of
/// `hkbBindable` is `SERIALIZE_IGNORED` runtime cache. Havok writes ignored
/// members as zeros rather than omitting them, so these offsets are absolute.
nonisolated public struct HKBNodeHeader: Equatable, Sendable {
    public let variableBindingSet: HKXPointerTarget?
    public let userData: UInt64
    public let name: String?

    private static let variableBindingSetField = HKXField(0x10, "m_variableBindingSet")
    private static let userDataField = HKXField(0x30, "m_userData")
    private static let nameField = HKXField(0x38, "m_name")

    /// Reads the inherited members from a cursor already positioned on the
    /// derived object. A null binding set is the common case, not a fault, so
    /// the miss it records is the ordinary `noFixup`.
    public static func decode(_ cursor: inout HKXObjectCursor) -> HKBNodeHeader {
        HKBNodeHeader(
            variableBindingSet: cursor.pointer(at: variableBindingSetField),
            userData: cursor.uint64(at: userDataField) ?? 0,
            name: cursor.string(at: nameField)
        )
    }

    public var references: [HKBReference] {
        HKBReference.optional("m_variableBindingSet", variableBindingSet)
    }
}

/// `hkbModifier`'s own serialized member on top of `hkbNode`: the enable flag.
nonisolated public struct HKBModifierHeader: Equatable, Sendable {
    public let node: HKBNodeHeader
    public let enable: Bool

    private static let enableField = HKXField(0x48, "m_enable")

    public static func decode(_ cursor: inout HKXObjectCursor) -> HKBModifierHeader {
        HKBModifierHeader(
            node: HKBNodeHeader.decode(&cursor),
            enable: cursor.bool(at: enableField) ?? false
        )
    }

    public var name: String? {
        node.name
    }

    public var references: [HKBReference] {
        node.references
    }
}

/// `hkbEventProperty` (and its `hkbEventBase` base, which is byte-identical):
/// an event index into `hkbBehaviorGraphData::m_eventInfos` plus an optional
/// payload object. 16 bytes, always embedded in an owning class rather than
/// registered as an object of its own.
nonisolated public struct HKBEventProperty: Equatable, Sendable {
    /// Index into the graph's event list; -1 means no event.
    public let id: Int
    public let payload: HKXPointerTarget?

    private static let idField = HKXField(0x00, "m_id")
    private static let payloadField = HKXField(0x08, "m_payload")

    public static let stride = 16

    /// Reads the embedded struct at `offset` bytes into the object the cursor
    /// sits on. Member names are prefixed with the owning member so a miss
    /// names `m_alarmEvent.m_payload` rather than a bare `m_payload`.
    public static func decode(
        _ cursor: inout HKXObjectCursor,
        at offset: Int,
        named member: String
    ) -> HKBEventProperty {
        HKBEventProperty(
            id: cursor.int32(at: HKXField(offset + idField.offset, "\(member).m_id")) ?? -1,
            payload: cursor.pointer(
                at: HKXField(offset + payloadField.offset, "\(member).m_payload")
            )
        )
    }

    public func references(named member: String) -> [HKBReference] {
        HKBReference.optional("\(member).m_payload", payload)
    }
}
