// Member reader for one Havok packfile object (todo 14.1). A class decoder
// declares its member offsets as `HKXField` constants and reads them through
// this cursor; the fixup arithmetic, the bounds checks, and the miss log all
// live here. See HKXObjectGraph.swift for the layout rules and the reasons a
// field can fail to resolve. Typed array reads are in the satellite file
// HKXObjectCursorArrays.swift.

import Foundation

/// A read position on one object: section index plus the object's section-local
/// base offset. Every accessor is `mutating` because a failed resolution
/// appends to `unresolved` instead of throwing — the log is the record the
/// acceptance calls for, so it is part of the read, not a side channel.
nonisolated struct HKXObjectCursor {
    let graph: HKXObjectGraph
    let sectionIndex: Int
    /// Section-local offset of the object (or array element) this cursor reads.
    let base: Int
    /// The owning section's payload; element cursors may sit in another
    /// section than the object that pointed at them.
    let payload: Data

    /// Every field this cursor failed to resolve, in read order.
    private(set) var unresolved: [HKXUnresolvedReference] = []

    /// Records one miss. Satellite readers append through this rather than
    /// touching the log directly.
    mutating func recordMiss(_ field: HKXField, _ miss: HKXResolutionMiss) {
        unresolved.append(HKXUnresolvedReference(
            sectionIndex: sectionIndex,
            objectOffset: base,
            field: field.name,
            miss: miss
        ))
    }

    /// Absorbs another cursor's log, so a decoder that follows a pointer keeps
    /// one flat list of misses for the whole object it built.
    mutating func absorb(_ other: HKXObjectCursor) {
        unresolved += other.unresolved
    }

    /// True when `length` bytes at the section-local `offset` lie inside the
    /// payload. Written without `offset + length` so a hostile length cannot
    /// overflow the sum past the check.
    func containsSectionRange(_ offset: Int, _ length: Int) -> Bool {
        offset >= 0 && length >= 0 && length <= payload.count && offset <= payload.count - length
    }

    // MARK: - Scalars

    mutating func uint8(at field: HKXField) -> UInt8? {
        scalar(at: field, size: 1) { try $0.readUInt8() }
    }

    mutating func int8(at field: HKXField) -> Int? {
        scalar(at: field, size: 1) { try Int(Int8(bitPattern: $0.readUInt8())) }
    }

    mutating func int16(at field: HKXField) -> Int? {
        scalar(at: field, size: 2) { try Int(Int16(bitPattern: $0.readUInt16())) }
    }

    mutating func int32(at field: HKXField) -> Int? {
        scalar(at: field, size: 4) { try Int(Int32(bitPattern: $0.readUInt32())) }
    }

    mutating func uint32(at field: HKXField) -> UInt32? {
        scalar(at: field, size: 4) { try $0.readUInt32() }
    }

    mutating func uint64(at field: HKXField) -> UInt64? {
        scalar(at: field, size: 8) { try $0.readUInt64() }
    }

    mutating func float32(at field: HKXField) -> Float? {
        scalar(at: field, size: 4) { try $0.readFloat32() }
    }

    /// Reads one fixed-width value at `base + field.offset`, recording an
    /// out-of-bounds miss rather than throwing.
    private mutating func scalar<Value>(
        at field: HKXField,
        size: Int,
        _ read: (inout BinaryReader) throws -> Value
    ) -> Value? {
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

    /// Resolves an 8-byte pointer member through the local fixups first, then
    /// the global ones. Local wins because a same-section patch is the common
    /// case and no observed file registers both for one source offset.
    mutating func pointer(at field: HKXField) -> HKXPointerTarget? {
        let source = base + field.offset
        if let local = graph.localTarget(section: sectionIndex, from: source) {
            return HKXPointerTarget(sectionIndex: sectionIndex, dataOffset: local)
        }
        guard let global = graph.globalTarget(section: sectionIndex, from: source) else {
            recordMiss(field, .noFixup)
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
    mutating func string(at field: HKXField) -> String? {
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
        guard let value = try? reader.readZString(encoding: .ascii) else {
            recordMiss(field, .undecodableString)
            return nil
        }
        return value
    }

    // MARK: - hkArray descriptors

    /// Element count of an hkArray member, from the i32 size at `field + 8`.
    /// Nil means the descriptor itself is unreadable or reports a negative
    /// count; zero is a well-formed empty array.
    mutating func arrayCount(at field: HKXField) -> Int? {
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
    mutating func array(at field: HKXField) -> HKXArrayView? {
        guard let count = arrayCount(at: field), count > 0 else { return nil }
        guard let target = pointer(at: field) else { return nil }
        return HKXArrayView(
            sectionIndex: target.sectionIndex, dataOffset: target.dataOffset, count: count
        )
    }
}
