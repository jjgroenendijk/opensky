// hkbBehaviorGraph and hkbBehaviorGraphData decode (todo 14.1): the top of a
// Havok behavior file. The graph object names the file, points at its root
// generator (the node tree item 14.2 decodes), and points at its data; the
// data object holds the variable and event declarations that every node binds
// against. Nothing here evaluates anything — evaluation is 14.3 and 14.4.
//
// 64-bit member offsets from ret2end/HKX2Library (MIT), whose class signatures
// match the local SSE files exactly (hkbBehaviorGraph 0xB1218F86,
// hkbBehaviorGraphData 0x095ACA5D), cross-checked against soulsmods/DSMapStudio
// HKX2 (MIT) for the VariableType ordering. Members flagged SERIALIZE_IGNORED
// by Havok still occupy their bytes in a packfile, so the offsets below are
// absolute in-memory offsets, not a packed sequence. No Havok SDK or Bethesda
// code consulted (AGENTS.md Legal & IP). Byte map and citations:
// docs/formats/hkx-behavior.md.

import Foundation

/// `hkbVariableInfo::VariableType` — the declared type of one graph variable
/// or character property. Values from soulsmods/DSMapStudio HKX2 (MIT),
/// confirmed against the vanilla files by the naming convention Bethesda uses
/// for behavior variables (`b*` bool, `i*` int32, `f*` real); see the
/// Verification section of docs/formats/hkx-behavior.md.
nonisolated enum HKBVariableType: Int, Equatable, Sendable {
    case invalid = -1
    case bool = 0
    case int8 = 1
    case int16 = 2
    case int32 = 3
    case real = 4
    case pointer = 5
    case vector3 = 6
    case vector4 = 7
    case quaternion = 8

    /// True when the variable's initial value lives in the quad list rather
    /// than the word list of `hkbVariableValueSet`.
    var isQuad: Bool {
        self == .vector3 || self == .vector4 || self == .quaternion
    }
}

extension HKBVariableType: CustomStringConvertible {
    var description: String {
        switch self {
        case .invalid: "invalid"
        case .bool: "bool"
        case .int8: "int8"
        case .int16: "int16"
        case .int32: "int32"
        case .real: "real"
        case .pointer: "pointer"
        case .vector3: "vector3"
        case .vector4: "vector4"
        case .quaternion: "quaternion"
        }
    }
}

/// One entry of `hkbBehaviorGraphData::m_variableInfos`. `rawType` is kept
/// beside the decoded case so an unknown value from a modded file stays
/// reportable instead of being silently normalised.
nonisolated struct HKBVariableInfo: Equatable {
    let rawType: Int
    let type: HKBVariableType?
}

/// Decoded `hkbBehaviorGraphData`: the graph's declarations. Variable and
/// event indices used by nodes address these lists positionally, and the
/// matching names come from `stringData`.
nonisolated struct HKBBehaviorGraphData: Equatable {
    let attributeDefaults: [Float]
    let variableInfos: [HKBVariableInfo]
    let characterPropertyInfos: [HKBVariableInfo]
    /// One `hkbEventInfo::m_flags` per declared event.
    let eventFlags: [UInt32]
    let wordMinVariableValues: [Int]
    let wordMaxVariableValues: [Int]
    let variableInitialValues: HKBVariableValueSet?
    let stringData: HKBBehaviorGraphStringData?
    let unresolved: [HKXUnresolvedReference]

    static let className = "hkbBehaviorGraphData"

    // hkReferencedObject base is 16 bytes; six hkArray then two pointers.
    private static let attributeDefaultsField = HKXField(0x10, "m_attributeDefaults")
    private static let variableInfosField = HKXField(0x20, "m_variableInfos")
    private static let characterPropertyInfosField = HKXField(
        0x30, "m_characterPropertyInfos"
    )
    private static let eventInfosField = HKXField(0x40, "m_eventInfos")
    private static let wordMinField = HKXField(0x50, "m_wordMinVariableValues")
    private static let wordMaxField = HKXField(0x60, "m_wordMaxVariableValues")
    private static let initialValuesField = HKXField(0x70, "m_variableInitialValues")
    private static let stringDataField = HKXField(0x78, "m_stringData")

    /// hkbVariableInfo is 6 bytes: a 4-byte hkbRoleAttribute then an i8 type
    /// and one padding byte.
    private static let variableInfoStride = 6
    private static let variableInfoTypeField = HKXField(0x04, "m_type")
    /// hkbEventInfo is 4 bytes: a single u32 flags word.
    private static let eventInfoStride = 4

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBBehaviorGraphData?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let initialValues = cursor.pointer(at: initialValuesField)
            .flatMap { HKBVariableValueSet.decode(at: $0, in: graph) }
        let stringData = cursor.pointer(at: stringDataField)
            .flatMap { HKBBehaviorGraphStringData.decode(at: $0, in: graph) }
        return HKBBehaviorGraphData(
            attributeDefaults: cursor.float32Array(at: attributeDefaultsField) ?? [],
            variableInfos: variableInfos(
                at: variableInfosField, cursor: &cursor, graph: graph
            ),
            characterPropertyInfos: variableInfos(
                at: characterPropertyInfosField, cursor: &cursor, graph: graph
            ),
            eventFlags: eventFlags(cursor: &cursor, graph: graph),
            wordMinVariableValues: cursor.int32Array(at: wordMinField) ?? [],
            wordMaxVariableValues: cursor.int32Array(at: wordMaxField) ?? [],
            variableInitialValues: initialValues,
            stringData: stringData,
            unresolved: cursor.unresolved
                + (initialValues?.unresolved ?? [])
                + (stringData?.unresolved ?? [])
        )
    }

    private static func variableInfos(
        at field: HKXField,
        cursor: inout HKXObjectCursor,
        graph: HKXObjectGraph
    ) -> [HKBVariableInfo] {
        guard let view = cursor.array(at: field) else { return [] }
        var infos: [HKBVariableInfo] = []
        infos.reserveCapacity(view.count)
        for index in 0 ..< view.count {
            guard
                var element = graph.element(
                    of: view, index: index, stride: variableInfoStride
                )
            else {
                continue
            }
            let raw = element
                .int8(at: variableInfoTypeField) ?? Int(HKBVariableType.invalid.rawValue)
            infos.append(HKBVariableInfo(rawType: raw, type: HKBVariableType(rawValue: raw)))
            cursor.absorb(element)
        }
        return infos
    }

    private static func eventFlags(
        cursor: inout HKXObjectCursor,
        graph: HKXObjectGraph
    ) -> [UInt32] {
        guard let view = cursor.array(at: eventInfosField) else { return [] }
        var flags: [UInt32] = []
        flags.reserveCapacity(view.count)
        for index in 0 ..< view.count {
            guard
                var element = graph.element(
                    of: view, index: index, stride: eventInfoStride
                )
            else {
                continue
            }
            flags.append(element.uint32(at: HKXField(0x00, "m_flags")) ?? 0)
            cursor.absorb(element)
        }
        return flags
    }
}

/// Decoded `hkbBehaviorGraph`: the top-level generator of a behavior file.
/// `rootGenerator` is the entry point of the node tree that item 14.2 decodes;
/// this item records where it is and what class it is, not what it does.
nonisolated struct HKBBehaviorGraph: Equatable {
    let name: String?
    let userData: UInt64
    /// `hkbBehaviorGraph::m_variableMode` — how the graph treats variables
    /// when it is instanced (0 discards, 1 maintains them across activation).
    let variableMode: Int
    let rootGenerator: HKXPointerTarget?
    let rootGeneratorClassName: String?
    let data: HKBBehaviorGraphData?
    let unresolved: [HKXUnresolvedReference]

    static let className = "hkbBehaviorGraph"

    // hkbBehaviorGraph derives hkbGenerator -> hkbNode -> hkbBindable ->
    // hkReferencedObject, so the inherited members land first: hkbBindable
    // ends at 0x30, hkbNode holds m_userData at 0x30 and m_name at 0x38 and
    // ends at 0x48, and hkbBehaviorGraph's own members start there.
    private static let userDataField = HKXField(0x30, "m_userData")
    private static let nameField = HKXField(0x38, "m_name")
    private static let variableModeField = HKXField(0x48, "m_variableMode")
    private static let rootGeneratorField = HKXField(0x80, "m_rootGenerator")
    private static let dataField = HKXField(0x88, "m_data")

    /// Every hkbBehaviorGraph in the packfile, in inventory order. Vanilla
    /// behavior files carry exactly one.
    static func graphs(in graph: HKXObjectGraph) -> [HKBBehaviorGraph] {
        graph.objects(ofClass: className).compactMap { decode(at: $0, in: graph) }
    }

    static func decode(at object: HKXObjectRef, in graph: HKXObjectGraph) -> HKBBehaviorGraph? {
        let target = HKXPointerTarget(
            sectionIndex: object.sectionIndex, dataOffset: object.dataOffset
        )
        return decode(at: target, in: graph)
    }

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBBehaviorGraph?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let rootGenerator = cursor.pointer(at: rootGeneratorField)
        let data = cursor.pointer(at: dataField)
            .flatMap { HKBBehaviorGraphData.decode(at: $0, in: graph) }
        return HKBBehaviorGraph(
            name: cursor.string(at: nameField),
            userData: cursor.uint64(at: userDataField) ?? 0,
            variableMode: cursor.int8(at: variableModeField) ?? 0,
            rootGenerator: rootGenerator,
            rootGeneratorClassName: rootGenerator.flatMap { graph.className(at: $0) },
            data: data,
            unresolved: cursor.unresolved + (data?.unresolved ?? [])
        )
    }
}
