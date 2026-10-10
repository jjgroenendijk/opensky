// Member reader for one Havok packfile object. A class decoder
// declares its member offsets as `HKXField` constants and reads them through
// this cursor; the fixup arithmetic, the bounds checks, and the miss log all
// live here. See HKXObjectGraph.swift for the layout rules and the reasons a
// field can fail to resolve. Typed array reads are in the satellite file
// HKXObjectCursorArrays.swift.

import Foundation
import OpenSkyFormatsCore

/// A read position on one object: section index plus the object's section-local
/// base offset. Every accessor is `mutating` because a failed resolution
/// appends to `unresolved` instead of throwing — the log is the record the
/// acceptance calls for, so it is part of the read, not a side channel.
nonisolated public struct HKXObjectCursor: Sendable {
    public let graph: HKXObjectGraph
    public let sectionIndex: Int
    /// Section-local offset of the object (or array element) this cursor reads.
    public let base: Int
    /// The owning section's payload; element cursors may sit in another
    /// section than the object that pointed at them.
    public let payload: Data
    /// The object, struct, or element value when this cursor reads a tagfile.
    public var tagValue: HKTValue?

    /// Every field this cursor failed to resolve, in read order.
    public private(set) var unresolved: [HKXUnresolvedReference] = []

    /// Records one miss. Satellite readers append through this rather than
    /// touching the log directly.
    public mutating func recordMiss(_ field: HKXField, _ miss: HKXResolutionMiss) {
        unresolved.append(HKXUnresolvedReference(
            objectOffset: base,
            field: field.name,
            miss: miss
        ))
    }

    /// Absorbs another cursor's log, so a decoder that follows a pointer keeps
    /// one flat list of misses for the whole object it built.
    public mutating func absorb(_ other: HKXObjectCursor) {
        unresolved += other.unresolved
    }

    /// True when `length` bytes at the section-local `offset` lie inside the
    /// payload. Written without `offset + length` so a hostile length cannot
    /// overflow the sum past the check.
    public func containsSectionRange(_ offset: Int, _ length: Int) -> Bool {
        offset >= 0 && length >= 0 && length <= payload.count && offset <= payload.count - length
    }

    // MARK: - Scalars

    public mutating func uint8(at field: HKXField) -> UInt8? {
        scalar(at: field, size: 1) { try $0.readUInt8() }
    }

    public mutating func int8(at field: HKXField) -> Int? {
        scalar(at: field, size: 1) { try Int(Int8(bitPattern: $0.readUInt8())) }
    }

    public mutating func int16(at field: HKXField) -> Int? {
        scalar(at: field, size: 2) { try Int(Int16(bitPattern: $0.readUInt16())) }
    }

    public mutating func uint16(at field: HKXField) -> Int? {
        scalar(at: field, size: 2) { try Int($0.readUInt16()) }
    }

    public mutating func int32(at field: HKXField) -> Int? {
        scalar(at: field, size: 4) { try Int(Int32(bitPattern: $0.readUInt32())) }
    }

    public mutating func uint32(at field: HKXField) -> UInt32? {
        scalar(at: field, size: 4) { try $0.readUInt32() }
    }

    public mutating func uint64(at field: HKXField) -> UInt64? {
        scalar(at: field, size: 8) { try $0.readUInt64() }
    }

    public mutating func float32(at field: HKXField) -> Float? {
        scalar(at: field, size: 4) { try $0.readFloat32() }
    }

    /// Reads a Havok `hkBool`, which occupies one byte with any non-zero value
    /// meaning true.
    public mutating func bool(at field: HKXField) -> Bool? {
        uint8(at: field).map { $0 != 0 }
    }

    /// Reads an `hkVector4` or `hkQuaternion`: four consecutive floats, 16-byte
    /// aligned in every class layout that carries one.
    public mutating func vector4(at field: HKXField) -> SIMD4<Float>? {
        scalar(at: field, size: 16) { reader in
            try SIMD4(
                reader.readFloat32(), reader.readFloat32(),
                reader.readFloat32(), reader.readFloat32()
            )
        }
    }

    /// Reads one fixed-width value at `base + field.offset`, recording an
    /// out-of-bounds miss rather than throwing.
    private mutating func scalar<Value>(
        at field: HKXField,
        size: Int,
        _ read: (inout BinaryReader) throws -> Value
    ) -> Value? {
        if tagValue != nil {
            var reader = BinaryReader(tagBytes(at: field, size: size))
            return try? read(&reader)
        }
        let offset = base + field.offset
        guard containsSectionRange(offset, size) else {
            recordMiss(field, .outOfBounds)
            return nil
        }
        var reader = BinaryReader(payload, offset: offset)
        guard let value = try? read(&reader) else {
            recordMiss(field, .outOfBounds)
            return nil
        }
        return value
    }

    // MARK: - Pointers and strings

    /// Resolves a pointer through the local fixups, then the global ones. The
    /// member is bounds-checked first, so a truncated object reports `outOfBounds`
    /// rather than `noFixup`.
    public mutating func pointer(at field: HKXField) -> HKXPointerTarget? {
        resolvePointer(at: field, recordingNull: true)
    }

    /// `pointer(at:)` for a member Havok may leave null, such as
    /// `m_extractedMotion`: a null is not logged as a miss, other failures are.
    public mutating func optionalPointer(at field: HKXField) -> HKXPointerTarget? {
        resolvePointer(at: field, recordingNull: false)
    }

    private mutating func resolvePointer(
        at field: HKXField,
        recordingNull: Bool
    ) -> HKXPointerTarget? {
        if tagValue != nil {
            let target = tagPointer(at: field)
            if target == nil, recordingNull {
                recordMiss(field, .noFixup)
            }
            return target
        }
        let source = base + field.offset
        guard containsSectionRange(source, Self.pointerStride) else {
            recordMiss(field, .outOfBounds)
            return nil
        }
        if let local = graph.localTarget(section: sectionIndex, from: source) {
            return HKXPointerTarget(sectionIndex: sectionIndex, dataOffset: local)
        }
        guard let global = graph.globalTarget(section: sectionIndex, from: source) else {
            if recordingNull {
                recordMiss(field, .noFixup)
            }
            return nil
        }
        guard graph.payload(ofSection: global.sectionIndex) != nil else {
            recordMiss(field, .sectionMissing)
            return nil
        }
        return global
    }

    /// Reads an hkStringPtr member: pointer to an in-place NUL-terminated
    /// ASCII string. A null pointer is how Havok writes an *absent* string,
    /// which is not the same as an empty one, so the miss is recorded and nil
    /// returned rather than `""` invented.
    public mutating func string(at field: HKXField) -> String? {
        if tagValue != nil {
            guard case let .string(value?)? = tagged(field) else {
                recordMiss(field, .noFixup)
                return nil
            }
            return value
        }
        guard let target = pointer(at: field) else { return nil }
        guard let stringPayload = graph.payload(ofSection: target.sectionIndex) else {
            recordMiss(field, .sectionMissing)
            return nil
        }
        guard target.dataOffset >= 0, target.dataOffset < stringPayload.count else {
            recordMiss(field, .outOfBounds)
            return nil
        }
        var reader = BinaryReader(stringPayload, offset: target.dataOffset)
        guard let value = try? reader.readZString(.strict(.ascii)) else {
            recordMiss(field, .undecodableString)
            return nil
        }
        return value
    }

    // MARK: - hkArray descriptors

    /// Element count of an hkArray member, from the i32 size at `field + 8`.
    /// Nil means the descriptor itself is unreadable or reports a negative
    /// count; zero is a well-formed empty array.
    public mutating func arrayCount(at field: HKXField) -> Int? {
        if tagValue != nil {
            return tagArray(at: field).count
        }
        let sizeField = HKXField(field.offset + 8, field.name)
        guard let count = int32(at: sizeField) else { return nil }
        guard count >= 0 else {
            recordMiss(field, .negativeCount)
            return nil
        }
        return count
    }

    /// Locates an hkArray's element data. Nil when the count is unreadable or
    /// negative, when the array is empty, or when a non-empty array carries no
    /// fixup to its elements — an empty array is null on disk with no fixup, so
    /// callers guard on `arrayCount` first when the distinction matters.
    public mutating func array(at field: HKXField) -> HKXArrayView? {
        guard let count = arrayCount(at: field), count > 0 else { return nil }
        if tagValue != nil {
            return HKXArrayView(
                sectionIndex: HKXObjectGraph.tagSection, dataOffset: 0, count: count,
                tagged: tagArray(at: field)
            )
        }
        guard let target = pointer(at: field) else { return nil }
        return HKXArrayView(
            sectionIndex: target.sectionIndex, dataOffset: target.dataOffset, count: count
        )
    }
}
