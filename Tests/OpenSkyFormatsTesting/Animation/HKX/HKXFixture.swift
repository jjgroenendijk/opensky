// Synthetic HKX packfile builder for the container tests. Layout follows the
// SSE 64-bit map in docs/formats/hkx-container.md. Signatures and names are
// invented. Uses `Data.appendUInt32`/`appendUInt64` from BSAFixture.swift.

import Foundation
@testable import OpenSkyFormatsAnimation

/// Builds a minimal spec-conformant HKX packfile blob. Knobs corrupt one axis
/// at a time so each parser guard has an isolated fixture.
public struct HKXFixture: Sendable {
    public struct LocalFixup: Sendable {
        public var from: UInt32
        public var toOffset: UInt32

        public init(from: UInt32, toOffset: UInt32) {
            self.from = from
            self.toOffset = toOffset
        }
    }

    public struct GlobalFixup: Sendable {
        public var from: UInt32
        public var toSection: UInt32
        public var toOffset: UInt32

        public init(from: UInt32, toSection: UInt32, toOffset: UInt32) {
            self.from = from
            self.toSection = toSection
            self.toOffset = toOffset
        }
    }

    public struct VirtualFixup: Sendable {
        public var dataOffset: UInt32
        public var classNameSection: UInt32
        public var classNameOffset: UInt32

        public init(dataOffset: UInt32, classNameSection: UInt32, classNameOffset: UInt32) {
            self.dataOffset = dataOffset
            self.classNameSection = classNameSection
            self.classNameOffset = classNameOffset
        }
    }

    // --- Well-formed defaults: valid 3-section file with one object at root. ---
    public var userTag: UInt32 = 0x1234_5678
    public var fileVersion: UInt32 = 8
    public var versionString = "hk_2010.2.0-r1"
    public var flags: UInt32 = 0
    /// (signature, name) pairs; synthetic hashes, real Havok type names.
    public var classNames: [(signature: UInt32, name: String)] = [
        (0x0BD4_C87B, "hkClass"),
        (0x0B5F_0E29, "hkClassMember"),
        (0x6DAB_825E, "hkRootLevelContainer")
    ]
    /// Which class-name entry the header's contents pointer targets.
    public var rootClassIndex = 2
    public var dataPayloadSize = 48
    /// Replaces the deterministic payload pattern with exact bytes (object
    /// decoding tests supply a hand-built hkaSkeleton payload). When set the
    /// __data__ section's data size follows the override length.
    public var payloadOverride: Data?
    public var localFixups: [LocalFixup] = [LocalFixup(from: 0, toOffset: 16)]
    public var globalFixups: [GlobalFixup] = [GlobalFixup(from: 4, toSection: 2, toOffset: 32)]
    /// Extra objects beyond the auto root object (`rootObjectDataOffset`).
    public var virtualFixups: [VirtualFixup] = []
    /// When set, build adds a virtual fixup registering the root object.
    public var rootObjectDataOffset: Int? = 0

    // --- Layout indices in the header (defaults match SSE files). ---
    public var contentsSectionIndex: UInt32 = 2
    public var contentsSectionOffset: UInt32 = 0
    public var contentsClassNameSectionIndex: UInt32 = 0
    /// Overrides the computed root name-string offset when set.
    public var contentsClassNameOffsetOverride: Int?

    // --- Corruption knobs (each isolated to one guard). ---
    public var badMagic = false
    public var pointerSize: UInt8 = 8
    public var littleEndian: UInt8 = 1
    public var sectionCountOverride: UInt32?
    public var truncateTo: Int?
    /// Inflates __data__ endOffset past EOF -> sectionOutOfBounds.
    public var dataEndOffsetOverride: Int?
    /// Swaps local/global offsets in __data__ header -> non-ascending.
    public var nonAscendingFixups = false
    /// Corrupts the 2nd class-name separator byte (0x09 -> 0x00) so the table
    /// parse stops early.
    public var badClassNameSeparator = false
    /// Pads each fixup region up to 16-byte alignment with a 0xFF tail (the
    /// 0xFFFFFFFF sentinel that must end a table).
    public var alignFixupRegions = false

    private static let headerSize = 64
    private static let sectionHeaderSize = 48
    private static let sectionCount = 3
    /// Data area begins right after the fixed header + 3 section headers.
    private static var dataAreaStart: Int {
        headerSize + sectionCount * sectionHeaderSize
    }

    public func build() -> Data {
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

    public init(
        userTag: UInt32 = 0x1234_5678,
        fileVersion: UInt32 = 8,
        versionString: String = "hk_2010.2.0-r1",
        flags: UInt32 = 0,
        classNames: [(signature: UInt32, name: String)] = [
            (0x0BD4_C87B, "hkClass"),
            (0x0B5F_0E29, "hkClassMember"),
            (0x6DAB_825E, "hkRootLevelContainer")
        ],
        rootClassIndex: Int = 2,
        dataPayloadSize: Int = 48,
        payloadOverride: Data? = nil,
        localFixups: [LocalFixup] = [LocalFixup(from: 0, toOffset: 16)],
        globalFixups: [GlobalFixup] = [GlobalFixup(from: 4, toSection: 2, toOffset: 32)],
        virtualFixups: [VirtualFixup] = [],
        rootObjectDataOffset: Int? = 0,
        contentsSectionIndex: UInt32 = 2,
        contentsSectionOffset: UInt32 = 0,
        contentsClassNameSectionIndex: UInt32 = 0,
        contentsClassNameOffsetOverride: Int? = nil,
        badMagic: Bool = false,
        pointerSize: UInt8 = 8,
        littleEndian: UInt8 = 1,
        sectionCountOverride: UInt32? = nil,
        truncateTo: Int? = nil,
        dataEndOffsetOverride: Int? = nil,
        nonAscendingFixups: Bool = false,
        badClassNameSeparator: Bool = false,
        alignFixupRegions: Bool = false
    ) {
        self.userTag = userTag
        self.fileVersion = fileVersion
        self.versionString = versionString
        self.flags = flags
        self.classNames = classNames
        self.rootClassIndex = rootClassIndex
        self.dataPayloadSize = dataPayloadSize
        self.payloadOverride = payloadOverride
        self.localFixups = localFixups
        self.globalFixups = globalFixups
        self.virtualFixups = virtualFixups
        self.rootObjectDataOffset = rootObjectDataOffset
        self.contentsSectionIndex = contentsSectionIndex
        self.contentsSectionOffset = contentsSectionOffset
        self.contentsClassNameSectionIndex = contentsClassNameSectionIndex
        self.contentsClassNameOffsetOverride = contentsClassNameOffsetOverride
        self.badMagic = badMagic
        self.pointerSize = pointerSize
        self.littleEndian = littleEndian
        self.sectionCountOverride = sectionCountOverride
        self.truncateTo = truncateTo
        self.dataEndOffsetOverride = dataEndOffsetOverride
        self.nonAscendingFixups = nonAscendingFixups
        self.badClassNameSeparator = badClassNameSeparator
        self.alignFixupRegions = alignFixupRegions
    }
}
