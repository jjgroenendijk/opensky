// Synthetic Havok packfile (HKX) byte builder shared by HKX container tests.
// Fixtures are built in code — never extracted game files (AGENTS.md "Legal &
// IP boundary"). Layout follows the SSE hk_2010.2.0-r1 64-bit packfile map in
// docs/formats/hkx-container.md (header 64B, section headers 48B, class-name
// table, fixup tables). Signatures + names below are invented, not copied.
//
// Reuses the `Data.appendUInt32`/`appendUInt64` helpers from BSAFixture.swift.

import Foundation
@testable import opensky

/// Builds a minimal spec-conformant HKX packfile blob. Knobs corrupt one axis
/// at a time so each parser guard has an isolated fixture.
struct HKXFixture {
    struct LocalFixup {
        var from: UInt32
        var toOffset: UInt32
    }

    struct GlobalFixup {
        var from: UInt32
        var toSection: UInt32
        var toOffset: UInt32
    }

    struct VirtualFixup {
        var dataOffset: UInt32
        var classNameSection: UInt32
        var classNameOffset: UInt32
    }

    // --- Well-formed defaults: valid 3-section file with one object at root. ---
    var userTag: UInt32 = 0x1234_5678
    var fileVersion: UInt32 = 8
    var versionString = "hk_2010.2.0-r1"
    var flags: UInt32 = 0
    /// (signature, name) pairs; synthetic hashes, real Havok type names.
    var classNames: [(signature: UInt32, name: String)] = [
        (0x0BD4_C87B, "hkClass"),
        (0x0B5F_0E29, "hkClassMember"),
        (0x6DAB_825E, "hkRootLevelContainer")
    ]
    /// Which class-name entry the header's contents pointer targets.
    var rootClassIndex = 2
    var dataPayloadSize = 48
    /// Replaces the deterministic payload pattern with exact bytes (object
    /// decoding tests supply a hand-built hkaSkeleton payload). When set the
    /// __data__ section's data size follows the override length.
    var payloadOverride: Data?
    var localFixups: [LocalFixup] = [LocalFixup(from: 0, toOffset: 16)]
    var globalFixups: [GlobalFixup] = [GlobalFixup(from: 4, toSection: 2, toOffset: 32)]
    /// Extra objects beyond the auto root object (`rootObjectDataOffset`).
    var virtualFixups: [VirtualFixup] = []
    /// When set, build adds a virtual fixup registering the root object.
    var rootObjectDataOffset: Int? = 0

    // --- Layout indices in the header (defaults match SSE files). ---
    var contentsSectionIndex: UInt32 = 2
    var contentsSectionOffset: UInt32 = 0
    var contentsClassNameSectionIndex: UInt32 = 0
    /// Overrides the computed root name-string offset when set.
    var contentsClassNameOffsetOverride: Int?

    // --- Corruption knobs (each isolated to one guard). ---
    var badMagic = false
    var pointerSize: UInt8 = 8
    var littleEndian: UInt8 = 1
    var sectionCountOverride: UInt32?
    var truncateTo: Int?
    /// Inflates __data__ endOffset past EOF -> sectionOutOfBounds.
    var dataEndOffsetOverride: Int?
    /// Swaps local/global offsets in __data__ header -> non-ascending.
    var nonAscendingFixups = false
    /// Corrupts the 2nd class-name separator byte (0x09 -> 0x00) so the table
    /// parse stops early.
    var badClassNameSeparator = false
    /// Pads each fixup region up to 16-byte alignment with a 0xFF tail (the
    /// 0xFFFFFFFF sentinel that must end a table).
    var alignFixupRegions = false

    private static let headerSize = 64
    private static let sectionHeaderSize = 48
    private static let sectionCount = 3
    /// Data area begins right after the fixed header + 3 section headers.
    private static var dataAreaStart: Int {
        headerSize + sectionCount * sectionHeaderSize
    }

    /// Deterministic payload pattern so slice tests can assert exact bytes,
    /// or the caller's exact override.
    var payloadBytes: Data {
        payloadOverride ?? Data((0 ..< dataPayloadSize).map { UInt8($0 & 0xFF) })
    }

    /// Class-name blob + each entry's section-local name-string offset
    /// (entry start + 5, matching HKXFile's `nameOffset` rule).
    func classNameLayout() -> (blob: Data, nameOffsets: [Int]) {
        var blob = Data()
        var nameOffsets: [Int] = []
        for (index, entry) in classNames.enumerated() {
            nameOffsets.append(blob.count + 5)
            blob.appendUInt32(entry.signature)
            let separator: UInt8 = (badClassNameSeparator && index == 1) ? 0x00 : 0x09
            blob.append(separator)
            blob.append(Data(entry.name.utf8))
            blob.append(0) // zstring terminator
        }
        blob.appendUInt32(0xFFFF_FFFF) // sentinel ends the table
        while blob.count % 16 != 0 {
            blob.append(0xFF)
        } // 0xFF tail padding
        return (blob, nameOffsets)
    }

    var classNamesBlob: Data {
        classNameLayout().blob
    }

    func nameOffset(ofClass index: Int) -> Int {
        classNameLayout().nameOffsets[index]
    }

    var rootNameOffset: Int {
        nameOffset(ofClass: rootClassIndex)
    }

    func build() -> Data {
        let (classBlob, nameOffsets) = classNameLayout()
        let classnamesStart = Self.dataAreaStart
        let dataStart = classnamesStart + classBlob.count // __types__ shares this

        // __data__ body: payload then local/global/virtual fixup regions.
        var body = payloadBytes
        let localOffset = body.count
        for fixup in localFixups {
            body.appendUInt32(fixup.from)
            body.appendUInt32(fixup.toOffset)
        }
        padRegion(&body, dataStart: dataStart)
        let globalOffset = body.count
        for fixup in globalFixups {
            body.appendUInt32(fixup.from)
            body.appendUInt32(fixup.toSection)
            body.appendUInt32(fixup.toOffset)
        }
        padRegion(&body, dataStart: dataStart)
        let virtualOffset = body.count
        for fixup in virtualObjects(nameOffsets: nameOffsets) {
            body.appendUInt32(fixup.dataOffset)
            body.appendUInt32(fixup.classNameSection)
            body.appendUInt32(fixup.classNameOffset)
        }
        padRegion(&body, dataStart: dataStart)
        let endOffset = dataEndOffsetOverride ?? body.count

        var out = buildHeader(rootNameOffset: nameOffsets[rootClassIndex])
        out.append(classnamesSectionHeader(blobLength: classBlob.count))
        out.append(typesSectionHeader(dataStart: dataStart))
        out.append(dataSectionHeader(
            dataStart: dataStart,
            localOffset: localOffset,
            globalOffset: globalOffset,
            virtualOffset: virtualOffset,
            endOffset: endOffset
        ))
        out.append(classBlob)
        out.append(body)

        if let limit = truncateTo {
            return out.prefix(limit)
        }
        return out
    }

    // MARK: - Regions

    private func virtualObjects(nameOffsets: [Int]) -> [VirtualFixup] {
        var objects: [VirtualFixup] = []
        if let offset = rootObjectDataOffset {
            objects.append(VirtualFixup(
                dataOffset: UInt32(offset),
                classNameSection: contentsClassNameSectionIndex,
                classNameOffset: UInt32(nameOffsets[rootClassIndex])
            ))
        }
        objects += virtualFixups
        return objects
    }

    /// Pads to the next 16-byte boundary (or a full word-aligned block if
    /// already aligned) so a 0xFFFFFFFF sentinel always follows the entries.
    private func padRegion(_ body: inout Data, dataStart: Int) {
        guard alignFixupRegions else { return }
        var pad = (16 - ((dataStart + body.count) % 16)) % 16
        if pad == 0 {
            pad = 16
        }
        body.append(Data(repeating: 0xFF, count: pad))
    }

    // MARK: - Header

    private func buildHeader(rootNameOffset: Int) -> Data {
        var out = Data()
        out.appendUInt32(badMagic ? 0xDEAD_BEEF : HKXHeader.magic0)
        out.appendUInt32(HKXHeader.magic1)
        out.appendUInt32(userTag)
        out.appendUInt32(fileVersion)
        out.append(contentsOf: [pointerSize, littleEndian, 0, 1]) // ptr/endian/reuse/empty-base
        out.appendUInt32(sectionCountOverride ?? UInt32(Self.sectionCount))
        out.appendUInt32(contentsSectionIndex)
        out.appendUInt32(contentsSectionOffset)
        out.appendUInt32(contentsClassNameSectionIndex)
        out.appendUInt32(UInt32(contentsClassNameOffsetOverride ?? rootNameOffset))
        out.append(versionField())
        out.appendUInt32(flags)
        out.appendUInt32(0xFFFF_FFFF) // pad
        return out
    }

    /// 16-byte field: name, NUL terminator, 0xFF fill.
    private func versionField() -> Data {
        var field = Data(versionString.utf8)
        field.append(0)
        while field.count < 16 {
            field.append(0xFF)
        }
        return field.prefix(16)
    }

    // MARK: - Section headers

    private func sectionHeader(name: String, offsets: [UInt32]) -> Data {
        var field = Data(name.utf8)
        field.append(Data(count: 19 - field.count)) // NUL pad name to 19
        field.append(0xFF) // separator
        for value in offsets {
            field.appendUInt32(value)
        }
        return field
    }

    /// __classnames__: no fixups, so all relative offsets equal the blob length.
    private func classnamesSectionHeader(blobLength: Int) -> Data {
        let blob = UInt32(blobLength)
        return sectionHeader(
            name: "__classnames__",
            offsets: [UInt32(Self.dataAreaStart), blob, blob, blob, blob, blob, blob]
        )
    }

    /// __types__: empty, sharing __data__'s start; all relative offsets 0.
    private func typesSectionHeader(dataStart: Int) -> Data {
        sectionHeader(name: "__types__", offsets: [UInt32(dataStart), 0, 0, 0, 0, 0, 0])
    }

    private func dataSectionHeader(
        dataStart: Int,
        localOffset: Int,
        globalOffset: Int,
        virtualOffset: Int,
        endOffset: Int
    ) -> Data {
        // Swapping local/global breaks the ascending-order invariant.
        let local = UInt32(nonAscendingFixups ? globalOffset : localOffset)
        let global = UInt32(nonAscendingFixups ? localOffset : globalOffset)
        let virtual = UInt32(virtualOffset)
        let end = UInt32(endOffset)
        return sectionHeader(
            name: "__data__",
            offsets: [UInt32(dataStart), local, global, virtual, end, end, end]
        )
    }
}
