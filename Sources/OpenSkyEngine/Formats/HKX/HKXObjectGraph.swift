// Shared Havok packfile object-graph resolution (todo 14.1). The container
// (6.1) locates objects; every object decoder then needs the same three
// operations — resolve a pointer field through the local plus global fixup
// tables, walk an hkArray descriptor to its element data, and read an in-place
// cstring. hkaSkeleton, hkaSplineCompressedAnimation, and hkaAnimationBinding
// each rebuilt those privately. Behavior graphs are pointer-dense (dozens of
// interlinked hkb classes referencing each other), so the duplication is
// factored here before item 14.2 multiplies it across node classes.
//
// Resolution never traps and never throws: an unresolvable field yields nil
// and appends an `HKXUnresolvedReference` carrying the reason, so a malformed
// file costs one field rather than the load. A caller that treats a field as
// load-bearing converts the nil into its own typed error.
//
// Layout rules (64-bit little-endian SSE packfiles, hk_2010.2.0-r1). Pointers
// are 8 bytes and null on disk — the Havok "finish" pass patches them at load,
// so the fixup tables *are* the pointer values. hkArray is
// `{ ptr(8) | i32 size @+8 | u32 capacityAndFlags @+12 }`, 16 bytes; the size
// field drives element counts because capacityAndFlags carries a flag in
// bit 31. hkStringPtr is an 8-byte pointer to an in-place NUL-terminated ASCII
// string. Sources and byte map: docs/formats/hkx-container.md.

import Foundation

/// One member of a Havok class: the section-local byte offset from the object
/// base plus the Havok member name, quoted verbatim by every unresolved
/// reference note so a census report names the field that failed.
nonisolated struct HKXField: Equatable {
    let offset: Int
    let name: String

    init(_ offset: Int, _ name: String) {
        self.offset = offset
        self.name = name
    }

    /// The element itself, for a cursor already positioned on an array
    /// element whose only member sits at offset 0 (hkStringPtr, pointer).
    static let element = HKXField(0, "element")
}

/// Why one field did not resolve. Recorded rather than thrown: the object
/// stays inspectable and the census reports the miss.
nonisolated enum HKXResolutionMiss: String, Equatable, Sendable {
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
nonisolated struct HKXUnresolvedReference: Equatable, Sendable {
    let sectionIndex: Int
    let objectOffset: Int
    let field: String
    let miss: HKXResolutionMiss
}

/// Located element data of one hkArray: where the elements start and how many
/// there are. The element stride is the reading class's business, so it stays
/// a parameter of the read rather than a member here.
nonisolated struct HKXArrayView: Equatable {
    let sectionIndex: Int
    let dataOffset: Int
    let count: Int
}

/// A resolved cross-object pointer: instance at `dataOffset` inside section
/// `sectionIndex`. Havok stores null on disk, so this is the fixup target, not
/// the stored pointer value.
nonisolated struct HKXPointerTarget: Equatable, Hashable {
    let sectionIndex: Int
    let dataOffset: Int
}

/// A packfile with its fixup tables indexed for lookup: section payloads,
/// local and global fixups keyed by source offset, and the class name of every
/// registered object keyed by its location. Build one per file and hand out
/// cursors; the indexes are shared by copy-on-write, so a cursor is cheap.
nonisolated struct HKXObjectGraph {
    let file: HKXFile

    /// Section payload (object data only) per section index.
    private let payloads: [Data]
    /// Per section: pointer source offset -> intra-section target offset.
    private let localTargets: [[Int: Int]]
    /// Per section: pointer source offset -> cross-section target.
    private let globalTargets: [[Int: HKXPointerTarget]]
    /// Object location -> class name, from the virtual-fixup inventory.
    private let classNames: [HKXPointerTarget: String]

    init(file: HKXFile) throws {
        self.file = file
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

    /// Every registered object of one class, in inventory order.
    func objects(ofClass name: String) -> [HKXObjectRef] {
        file.objects.filter { $0.className == name }
    }

    /// Class name of the object registered at `target`, nil when the location
    /// carries no virtual fixup (an inline struct rather than an instance).
    func className(at target: HKXPointerTarget) -> String? {
        classNames[target]
    }

    func payload(ofSection index: Int) -> Data? {
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
    func cursor(section: Int, offset: Int) -> HKXObjectCursor? {
        guard let payload = payload(ofSection: section), offset >= 0, offset < payload.count else {
            return nil
        }
        return HKXObjectCursor(graph: self, sectionIndex: section, base: offset, payload: payload)
    }

    func cursor(at target: HKXPointerTarget) -> HKXObjectCursor? {
        cursor(section: target.sectionIndex, offset: target.dataOffset)
    }

    func cursor(at object: HKXObjectRef) -> HKXObjectCursor? {
        cursor(section: object.sectionIndex, offset: object.dataOffset)
    }

    /// Cursor over one element of an array, so element members are read with
    /// the same API as object members. Elements may live in a different
    /// section than the object holding the descriptor, which is why this hangs
    /// off the graph rather than off the owning cursor.
    func element(of view: HKXArrayView, index: Int, stride: Int) -> HKXObjectCursor? {
        guard index >= 0, index < view.count, stride > 0 else { return nil }
        guard let payload = payload(ofSection: view.sectionIndex) else { return nil }
        let start = view.dataOffset + index * stride
        guard start >= 0, start + stride <= payload.count else { return nil }
        return HKXObjectCursor(
            graph: self, sectionIndex: view.sectionIndex, base: start, payload: payload
        )
    }
}
