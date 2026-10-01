// hkbBehaviorGraphStringData and hkbVariableValueSet decode. The graph names
// every variable, event, and property by index; these objects map an index
// back to a name and a starting value.
// Byte map and citations: docs/formats/hkx-behavior.md.

import Foundation

/// Decoded `hkbBehaviorGraphStringData`: the name tables the whole graph is
/// addressed through. Entries stay index-preserving — a null name is nil in
/// place, never dropped, because every index in the graph is positional.
nonisolated public struct HKBBehaviorGraphStringData: Equatable, Sendable {
    public let eventNames: [String?]
    public let attributeNames: [String?]
    public let variableNames: [String?]
    public let characterPropertyNames: [String?]
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbBehaviorGraphStringData"

    // hkReferencedObject base is 16 bytes; four hkArray<hkStringPtr> follow.
    private static let eventNamesField = HKXField(0x10, "m_eventNames")
    private static let attributeNamesField = HKXField(0x20, "m_attributeNames")
    private static let variableNamesField = HKXField(0x30, "m_variableNames")
    private static let characterPropertyNamesField = HKXField(
        0x40, "m_characterPropertyNames"
    )

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBBehaviorGraphStringData?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        return HKBBehaviorGraphStringData(
            eventNames: cursor.stringArray(at: eventNamesField),
            attributeNames: cursor.stringArray(at: attributeNamesField),
            variableNames: cursor.stringArray(at: variableNamesField),
            characterPropertyNames: cursor.stringArray(at: characterPropertyNamesField),
            unresolved: cursor.unresolved
        )
    }
}

/// Decoded `hkbVariableValueSet`: the initial value of every graph variable.
/// A variable's declared type decides which list its index addresses — word
/// values hold bool, int, and real variables (a real is the float bit pattern
/// stored in an i32), quad values hold vector and quaternion variables, and
/// variant values hold pointer variables.
nonisolated public struct HKBVariableValueSet: Equatable, Sendable {
    public let wordValues: [Int]
    public let quadValues: [SIMD4<Float>]
    /// Pointer-typed variables are references to other objects; the census
    /// needs only how many there are, so the targets are not followed here.
    public let variantCount: Int
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbVariableValueSet"

    private static let wordValuesField = HKXField(0x10, "m_wordVariableValues")
    private static let quadValuesField = HKXField(0x20, "m_quadVariableValues")
    private static let variantValuesField = HKXField(0x30, "m_variantVariableValues")
    /// hkVector4, four floats.
    private static let quadStride = 16

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBVariableValueSet?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        // hkbVariableValue is a 4-byte struct wrapping one i32, so an array of
        // them reads exactly like an hkArray<hkInt32>.
        let words = cursor.int32Array(at: wordValuesField) ?? []
        var quads: [SIMD4<Float>] = []
        if let view = cursor.array(at: quadValuesField) {
            for index in 0 ..< view.count {
                guard
                    var element = graph.element(
                        of: view, index: index, stride: quadStride
                    )
                else {
                    continue
                }
                quads.append(SIMD4(
                    element.float32(at: HKXField(0x00, "x")) ?? 0,
                    element.float32(at: HKXField(0x04, "y")) ?? 0,
                    element.float32(at: HKXField(0x08, "z")) ?? 0,
                    element.float32(at: HKXField(0x0C, "w")) ?? 0
                ))
                cursor.absorb(element)
            }
        }
        return HKBVariableValueSet(
            wordValues: words,
            quadValues: quads,
            variantCount: cursor.arrayCount(at: variantValuesField) ?? 0,
            unresolved: cursor.unresolved
        )
    }

    /// A real-typed variable stores its float in the word slot's bit pattern.
    public func realValue(at index: Int) -> Float? {
        guard wordValues.indices.contains(index) else { return nil }
        return Float(bitPattern: UInt32(bitPattern: Int32(truncatingIfNeeded: wordValues[index])))
    }
}
