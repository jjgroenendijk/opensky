// The `hkbBindable` leaf classes (todo 14.2): the variable binding set every
// node may carry, and the two bone-list classes generators and modifiers point
// at. None of them is a node — they have no name and no children — but they are
// registered objects in the packfile, so they need decoders like any other
// class.
//
// The binding set is the mechanism the whole graph is driven through: it maps a
// member path on the owning object ("m_blendParameter") to an index into
// `hkbBehaviorGraphData::m_variableInfos`, so writing a graph variable rewrites
// a node field. Item 14.3 evaluates that; here it is decoded and no more.
//
// 64-bit member offsets from ret2end/HKX2Library (MIT); signatures match the
// local SSE files (hkbVariableBindingSet 0x338AD4FF, hkbBoneWeightArray
// 0xCD902B77, hkbBoneIndexArray 0x00AA8619). Byte map and citations:
// docs/formats/hkx-behavior-nodes.md.

import Foundation

/// One entry of `hkbVariableBindingSet::m_bindings`, 40 bytes. The members
/// Havok flags `SERIALIZE_IGNORED` here are the resolved member pointer and the
/// cached offsets, which a packfile writes as zeros; the authored data is the
/// member path, the variable index, and how the two are joined.
nonisolated struct HKBVariableBinding: Equatable {
    /// Member path on the bound object, e.g. `m_blendParameter`. An empty path
    /// binds the object itself, which is how a generator is bound wholesale.
    let memberPath: String?
    /// Index into the graph's variable list, or into its character-property
    /// list when `bindingType` says so.
    let variableIndex: Int
    /// Which bit of a bool-packed variable this binding reads; -1 when the
    /// binding is not bit-addressed.
    let bitIndex: Int
    /// `hkbVariableBindingSet::Binding::BindingType`: 0 binds a graph variable,
    /// 1 binds a character property.
    let bindingType: Int

    static let stride = 40

    private static let memberPathField = HKXField(0x00, "m_memberPath")
    private static let variableIndexField = HKXField(0x1C, "m_variableIndex")
    private static let bitIndexField = HKXField(0x20, "m_bitIndex")
    private static let bindingTypeField = HKXField(0x21, "m_bindingType")

    static func decode(_ element: inout HKXObjectCursor) -> HKBVariableBinding {
        HKBVariableBinding(
            memberPath: element.string(at: memberPathField),
            variableIndex: element.int32(at: variableIndexField) ?? -1,
            bitIndex: element.int8(at: bitIndexField) ?? -1,
            bindingType: element.int8(at: bindingTypeField) ?? 0
        )
    }
}

/// Decoded `hkbVariableBindingSet`: every graph variable bound into one node.
nonisolated struct HKBVariableBindingSet: HKBClass, Equatable {
    let bindings: [HKBVariableBinding]
    /// Index of the binding that drives the owning node's enable flag, or -1.
    let indexOfBindingToEnable: Int
    let unresolved: [HKXUnresolvedReference]

    static let className = "hkbVariableBindingSet"

    private static let bindingsField = HKXField(0x10, "m_bindings")
    private static let indexOfBindingToEnableField = HKXField(
        0x20, "m_indexOfBindingToEnable"
    )

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBVariableBindingSet?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        var bindings: [HKBVariableBinding] = []
        if let view = cursor.array(at: bindingsField) {
            bindings.reserveCapacity(view.count)
            for index in 0 ..< view.count {
                guard
                    var element = graph.element(
                        of: view, index: index, stride: HKBVariableBinding.stride
                    )
                else {
                    cursor.recordMiss(bindingsField, .outOfBounds)
                    continue
                }
                bindings.append(HKBVariableBinding.decode(&element))
                cursor.absorb(element)
            }
        }
        return HKBVariableBindingSet(
            bindings: bindings,
            indexOfBindingToEnable: cursor.int32(at: indexOfBindingToEnableField) ?? -1,
            unresolved: cursor.unresolved
        )
    }

    var summary: String {
        "\(bindings.count) bindings, enable binding \(indexOfBindingToEnable)"
    }
}

/// Decoded `hkbBoneWeightArray`: one weight per skeleton bone, used by blender
/// children and by the Bethesda bone-switch generator to blend per bone.
nonisolated struct HKBBoneWeightArray: HKBClass, Equatable {
    let variableBindingSet: HKXPointerTarget?
    let boneWeights: [Float]
    let unresolved: [HKXUnresolvedReference]

    static let className = "hkbBoneWeightArray"

    // hkbBindable's binding set at 0x10, then this class's own member.
    private static let variableBindingSetField = HKXField(0x10, "m_variableBindingSet")
    private static let boneWeightsField = HKXField(0x30, "m_boneWeights")

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBBoneWeightArray?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        return HKBBoneWeightArray(
            variableBindingSet: cursor.pointer(at: variableBindingSetField),
            boneWeights: cursor.float32Array(at: boneWeightsField) ?? [],
            unresolved: cursor.unresolved
        )
    }

    var references: [HKBReference] {
        HKBReference.optional("m_variableBindingSet", variableBindingSet)
    }

    var summary: String {
        "\(boneWeights.count) bone weights"
    }
}

/// Decoded `hkbBoneIndexArray`: a bone subset, named by skeleton bone index.
nonisolated struct HKBBoneIndexArray: HKBClass, Equatable {
    let variableBindingSet: HKXPointerTarget?
    let boneIndices: [Int]
    let unresolved: [HKXUnresolvedReference]

    static let className = "hkbBoneIndexArray"

    private static let variableBindingSetField = HKXField(0x10, "m_variableBindingSet")
    private static let boneIndicesField = HKXField(0x30, "m_boneIndices")

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBBoneIndexArray?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        return HKBBoneIndexArray(
            variableBindingSet: cursor.pointer(at: variableBindingSetField),
            boneIndices: cursor.int16Array(at: boneIndicesField) ?? [],
            unresolved: cursor.unresolved
        )
    }

    var references: [HKBReference] {
        HKBReference.optional("m_variableBindingSet", variableBindingSet)
    }

    var summary: String {
        "\(boneIndices.count) bone indices"
    }
}

/// Decoded `hkbStringEventPayload`: the payload an event carries when the
/// authored data attaches a string to it. The only payload class the vanilla
/// player graph uses.
nonisolated struct HKBStringEventPayload: HKBClass, Equatable {
    let data: String?
    let unresolved: [HKXUnresolvedReference]

    static let className = "hkbStringEventPayload"

    private static let dataField = HKXField(0x10, "m_data")

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBStringEventPayload?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        return HKBStringEventPayload(
            data: cursor.string(at: dataField),
            unresolved: cursor.unresolved
        )
    }

    var summary: String {
        "payload \"\(data ?? "")\""
    }
}
