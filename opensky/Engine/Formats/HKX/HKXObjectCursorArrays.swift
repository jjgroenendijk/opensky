// Typed hkArray element readers for HKXObjectCursor (todo 14.1), split out of
// HKXObjectCursor.swift to stay under the file-size lint cap. Element strides
// are the Havok class sizes: 8 for a pointer or hkStringPtr, 4 for i32/u32/
// float, 2 for i16, 1 for a byte. See HKXObjectGraph.swift for the layout
// rules and the miss-logging contract.

import Foundation

nonisolated extension HKXObjectCursor {
    /// Pointer size on 64-bit packfiles; also the stride of an hkArray of
    /// pointers or of hkStringPtr.
    static let pointerStride = 8

    /// Elements of an `hkArray<hkStringPtr>`. Index-preserving: a null or
    /// unreadable element yields nil in place, because variable and event
    /// names are addressed by index and a compacted list would silently
    /// renumber them.
    mutating func stringArray(at field: HKXField) -> [String?] {
        guard let view = array(at: field) else { return [] }
        return (0 ..< view.count).map { index in
            guard
                var element = graph.element(
                    of: view, index: index, stride: Self.pointerStride
                )
            else {
                recordMiss(field, .outOfBounds)
                return nil
            }
            let value = element.string(at: .element)
            absorb(element)
            return value
        }
    }

    /// Elements of an `hkArray<T*>`, index-preserving for the same reason as
    /// `stringArray`.
    mutating func pointerArray(at field: HKXField) -> [HKXPointerTarget?] {
        guard let view = array(at: field) else { return [] }
        return (0 ..< view.count).map { index in
            guard
                var element = graph.element(
                    of: view, index: index, stride: Self.pointerStride
                )
            else {
                recordMiss(field, .outOfBounds)
                return nil
            }
            let value = element.pointer(at: .element)
            absorb(element)
            return value
        }
    }

    /// Elements of an `hkArray<hkInt16>`. Nil when any element is unreadable —
    /// index arrays are load-bearing, so a partial read is worse than none.
    mutating func int16Array(at field: HKXField) -> [Int]? {
        elements(at: field, stride: 2) { $0.int16(at: .element) }
    }

    /// Elements of an `hkArray<hkInt32>`.
    mutating func int32Array(at field: HKXField) -> [Int]? {
        elements(at: field, stride: 4) { $0.int32(at: .element) }
    }

    /// Elements of an `hkArray<hkUint32>`.
    mutating func uint32Array(at field: HKXField) -> [UInt32]? {
        elements(at: field, stride: 4) { $0.uint32(at: .element) }
    }

    /// Elements of an `hkArray<hkReal>`.
    mutating func float32Array(at field: HKXField) -> [Float]? {
        elements(at: field, stride: 4) { $0.float32(at: .element) }
    }

    /// Bytes of an `hkArray<hkUint8>`, read as one slice.
    mutating func byteArray(at field: HKXField) -> Data? {
        guard let view = array(at: field) else { return nil }
        guard let payload = graph.payload(ofSection: view.sectionIndex) else {
            recordMiss(field, .sectionMissing)
            return nil
        }
        guard
            view.dataOffset >= 0,
            view.count <= payload.count,
            view.dataOffset <= payload.count - view.count
        else {
            recordMiss(field, .outOfBounds)
            return nil
        }
        var reader = BinaryReader(payload, offset: view.dataOffset)
        guard let bytes = try? reader.read(count: view.count) else {
            recordMiss(field, .outOfBounds)
            return nil
        }
        return bytes
    }

    /// Reads every element of a fixed-stride array through an element cursor,
    /// failing the whole array on the first unreadable element.
    private mutating func elements<Value>(
        at field: HKXField,
        stride: Int,
        _ read: (inout HKXObjectCursor) -> Value?
    ) -> [Value]? {
        guard let view = array(at: field) else { return nil }
        var values: [Value] = []
        values.reserveCapacity(view.count)
        for index in 0 ..< view.count {
            guard var element = graph.element(of: view, index: index, stride: stride) else {
                recordMiss(field, .outOfBounds)
                return nil
            }
            guard let value = read(&element) else {
                absorb(element)
                recordMiss(field, .outOfBounds)
                return nil
            }
            absorb(element)
            values.append(value)
        }
        return values
    }
}
