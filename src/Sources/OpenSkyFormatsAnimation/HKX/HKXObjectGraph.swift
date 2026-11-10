// Havok packfile object-graph resolution shared by every object decoder:
// pointers through the fixup tables, hkArray elements, and in-place strings.
// Resolution never traps or throws; an unresolved field yields nil and an
// `HKXUnresolvedReference`. Layout: docs/formats/hkx-container.md.

public import Foundation
import OpenSkyFormatsCore

/// One member of a Havok class: the section-local byte offset from the object
/// base plus the Havok member name, quoted verbatim by every unresolved
/// reference note so a census report names the field that failed.
nonisolated public struct HKXField: Equatable, Sendable {
    public let offset: Int
    public let name: String

    public init(_ offset: Int, _ name: String) {
        self.offset = offset
        self.name = name
    }

    /// The element itself, for a cursor already positioned on an array
    /// element whose only member sits at offset 0 (hkStringPtr, pointer).
    public static let element = HKXField(0, "element")
}

/// Why one field did not resolve. Recorded rather than thrown: the object
/// stays inspectable and the census reports the miss.
nonisolated public enum HKXResolutionMiss: String, Equatable, Sendable {
    /// The pointer is null on disk and no fixup patches it.
    case noFixup
    /// The fixup targets a section the file does not define.
    case sectionMissing
    /// The field, or the data it points at, runs past the section payload.
    case outOfBounds
    /// An hkArray reports a negative element count.
    case negativeCount
    /// The bytes at a string pointer are not a terminated ASCII string.
    case undecodableString
}

/// One recorded resolution failure: which member of which object, and why.
nonisolated public struct HKXUnresolvedReference: Equatable, Sendable {
    public let objectOffset: Int
    public let field: String
    public let miss: HKXResolutionMiss
}

/// Located element data of one hkArray: where the elements start and how many
/// there are. The element stride is the reading class's business, so it stays
/// a parameter of the read rather than a member here.
nonisolated public struct HKXArrayView: Equatable, Sendable {
    public let sectionIndex: Int
    public let dataOffset: Int
    public let count: Int
    /// The elements themselves when the array came from a tagfile.
    public var tagged: [HKTValue]?
}

/// A resolved cross-object pointer: instance at `dataOffset` inside section
/// `sectionIndex`. Havok stores null on disk, so this is the fixup target, not
/// the stored pointer value.
nonisolated public struct HKXPointerTarget: Equatable, Hashable, Sendable {
    public let sectionIndex: Int
    public let dataOffset: Int

    public init(sectionIndex: Int, dataOffset: Int) {
        self.sectionIndex = sectionIndex
        self.dataOffset = dataOffset
    }
}

/// A packfile with its fixup tables indexed for lookup: section payloads,
/// local and global fixups keyed by source offset, and the class name of every
/// registered object keyed by its location. Build one per file and hand out
/// cursors; the indexes are shared by copy-on-write, so a cursor is cheap.
nonisolated public struct HKXObjectGraph: Sendable {
    /// The decoded tagfile behind a graph built with `init(tagfile:)`.
    public let tagfile: HKTagfile?
    /// Every registered object, in inventory order.
    public let objectRefs: [HKXObjectRef]

    /// Section payload (object data only) per section index.
    private let payloads: [Data]
    /// Per section: pointer source offset -> intra-section target offset.
    private let localTargets: [[Int: Int]]
    /// Per section: pointer source offset -> cross-section target.
    private let globalTargets: [[Int: HKXPointerTarget]]
    /// Object location -> class name, from the virtual-fixup inventory.
    private let classNames: [HKXPointerTarget: String]

    public init(file: HKXFile) throws {
        tagfile = nil
        objectRefs = file.objects
        var payloads: [Data] = []
        var localTargets: [[Int: Int]] = []
        var globalTargets: [[Int: HKXPointerTarget]] = []
        for (index, section) in file.sections.enumerated() {
            try payloads.append(file.sectionData(at: index))
            localTargets.append(Dictionary(
                section.localFixups.map { ($0.fromOffset, $0.toOffset) },
                uniquingKeysWith: { first, _ in first }
            ))
            globalTargets.append(Dictionary(
                section.globalFixups.map {
                    ($0.fromOffset, HKXPointerTarget(
                        sectionIndex: $0.sectionIndex, dataOffset: $0.toOffset
                    ))
                },
                uniquingKeysWith: { first, _ in first }
            ))
        }
        self.payloads = payloads
        self.localTargets = localTargets
        self.globalTargets = globalTargets
        classNames = Dictionary(
            file.objects.compactMap { object in
                object.className.map {
                    (HKXPointerTarget(
                        sectionIndex: object.sectionIndex, dataOffset: object.dataOffset
                    ), $0)
                }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// A graph over a tagfile's objects: each one sits in `tagSection` at its index,
    /// and a cursor reads its members by name instead of by offset.
    public init(tagfile: HKTagfile) {
        self.tagfile = tagfile
        objectRefs = tagfile.objects.indices.map { index in
            HKXObjectRef(
                sectionIndex: Self.tagSection, dataOffset: index, signature: nil,
                className: tagfile.className(of: tagfile.objects[index])
            )
        }
        payloads = []
        localTargets = []
        globalTargets = []
        classNames = [:]
    }

    /// Every registered object of one class, in inventory order.
    public func objects(ofClass name: String) -> [HKXObjectRef] {
        objectRefs.filter { $0.className == name }
    }

    /// Class name of the object registered at `target`, nil when the location
    /// carries no virtual fixup (an inline struct rather than an instance).
    public func className(at target: HKXPointerTarget) -> String? {
        if let object = tagObject(at: target), let tagfile {
            return tagfile.className(of: object)
        }
        return classNames[target]
    }

    public func payload(ofSection index: Int) -> Data? {
        payloads.indices.contains(index) ? payloads[index] : nil
    }

    /// Intra-section fixup target for a pointer stored at `offset`.
    func localTarget(section: Int, from offset: Int) -> Int? {
        localTargets.indices.contains(section) ? localTargets[section][offset] : nil
    }

    /// Cross-section fixup target for a pointer stored at `offset`.
    func globalTarget(section: Int, from offset: Int) -> HKXPointerTarget? {
        globalTargets.indices.contains(section) ? globalTargets[section][offset] : nil
    }

    /// Cursor over the object at a section-local offset.
    public func cursor(section: Int, offset: Int) -> HKXObjectCursor? {
        guard let payload = payload(ofSection: section), offset >= 0, offset < payload.count else {
            return nil
        }
        return HKXObjectCursor(graph: self, sectionIndex: section, base: offset, payload: payload)
    }

    public func cursor(at target: HKXPointerTarget) -> HKXObjectCursor? {
        if let object = tagObject(at: target) {
            return tagCursor(over: .structure(object), base: target.dataOffset)
        }
        return cursor(section: target.sectionIndex, offset: target.dataOffset)
    }

    public func cursor(at object: HKXObjectRef) -> HKXObjectCursor? {
        cursor(at: HKXPointerTarget(
            sectionIndex: object.sectionIndex, dataOffset: object.dataOffset
        ))
    }

    /// Cursor over one element of an array, so element members are read with
    /// the same API as object members. Elements may live in a different
    /// section than the object holding the descriptor, which is why this hangs
    /// off the graph rather than off the owning cursor.
    public func element(of view: HKXArrayView, index: Int, stride: Int) -> HKXObjectCursor? {
        guard index >= 0, index < view.count, stride > 0 else { return nil }
        if let tagged = view.tagged {
            return tagged.indices.contains(index) ? tagCursor(over: tagged[index]) : nil
        }
        guard let payload = payload(ofSection: view.sectionIndex) else { return nil }
        let start = view.dataOffset + index * stride
        guard start >= 0, start + stride <= payload.count else { return nil }
        return HKXObjectCursor(
            graph: self, sectionIndex: view.sectionIndex, base: start, payload: payload
        )
    }
}

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
    func containsSectionRange(_ offset: Int, _ length: Int) -> Bool {
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
            return attempt { try read(&reader) }
        }
        let offset = base + field.offset
        guard containsSectionRange(offset, size) else {
            recordMiss(field, .outOfBounds)
            return nil
        }
        var reader = BinaryReader(payload, offset: offset)
        guard let value = attempt({ try read(&reader) }) else {
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
        guard let value = attempt({ try reader.readZString(.strict(.ascii)) }) else {
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
