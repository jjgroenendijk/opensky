// Havok packfile container (todo 6.1): header + section table + class-name
// table + fixup-derived object inventory. No public Havok spec; layout from
// independent open parsers — exyorha/hkxparse (MIT) and ret2end/HKX2Library
// (MIT, SSE-specific) — plus ZeldaMods wiki "Havok"; every field verified by
// probe against SSE skeleton.hkx + idle .hkx (hk_2010.2.0-r1, 64-bit).
// Byte map + citations: docs/formats/hkx-container.md. Object internals
// (hkaSkeleton members etc.) are later milestone items; the container only
// locates objects, it cannot size them (needs class reflection).

import Foundation

/// One class-name table entry: type signature hash + name. `nameOffset` is
/// the section-local offset of the name string (entry start + 5) — the
/// offset virtual fixups and the header contents pointer reference.
nonisolated struct HKXClassName: Equatable {
    let signature: UInt32
    let name: String
    let nameOffset: Int
}

/// Object registration resolved against the class-name table: instance at
/// `dataOffset` inside section `sectionIndex`. `className` is nil when the
/// fixup references an offset the class-name table does not define
/// (malformed input stays inspectable, never traps).
nonisolated struct HKXObjectRef: Equatable {
    let sectionIndex: Int
    let dataOffset: Int
    let signature: UInt32?
    let className: String?
}

/// Parsed packfile container. Section payloads stay in `data`; use
/// `sectionData(at:)` to slice one for object-level decoding (6.2+).
nonisolated struct HKXFile {
    let data: Data
    let header: HKXHeader
    let sections: [HKXSection]
    /// Class-name entries of the header's contents class-name section
    /// (SSE: section 0, `__classnames__`).
    let classNames: [HKXClassName]

    init(data: Data) throws {
        self.data = data
        var reader = BinaryReader(data)
        header = try HKXHeader(reader: &reader)
        var sections: [HKXSection] = []
        for _ in 0 ..< header.sectionCount {
            let sectionHeader = try HKXSectionHeader(reader: &reader)
            try sections.append(HKXSection(header: sectionHeader, fileData: data))
        }
        self.sections = sections
        guard sections.indices.contains(header.contentsClassNameSectionIndex) else {
            throw HKXError.sectionIndexInvalid(header.contentsClassNameSectionIndex)
        }
        guard sections.indices.contains(header.contentsSectionIndex) else {
            throw HKXError.sectionIndexInvalid(header.contentsSectionIndex)
        }
        classNames = try Self.readClassNames(
            data,
            section: sections[header.contentsClassNameSectionIndex].header
        )
    }

    /// Raw payload of one section (object data only, fixup tables excluded).
    func sectionData(at index: Int) throws -> Data {
        guard sections.indices.contains(index) else {
            throw HKXError.sectionIndexInvalid(index)
        }
        let header = sections[index].header
        var reader = BinaryReader(data, offset: header.dataStart)
        return try reader.read(count: header.dataSize)
    }

    /// Class name at a section-local name-string offset (fixup target).
    func className(atOffset offset: Int) -> HKXClassName? {
        classNames.first { $0.nameOffset == offset }
    }

    /// Class name of the top-level object (SSE: "hkRootLevelContainer").
    var rootClassName: HKXClassName? {
        className(atOffset: header.contentsClassNameOffset)
    }

    /// Object inventory: every virtual fixup across all sections resolved
    /// against the class-name table, in file order.
    var objects: [HKXObjectRef] {
        var refs: [HKXObjectRef] = []
        for (index, section) in sections.enumerated() {
            for fixup in section.virtualFixups {
                let name = fixup.classNameSectionIndex
                    == header.contentsClassNameSectionIndex
                    ? className(atOffset: fixup.classNameOffset)
                    : nil
                refs.append(HKXObjectRef(
                    sectionIndex: index,
                    dataOffset: fixup.dataOffset,
                    signature: name?.signature,
                    className: name?.name
                ))
            }
        }
        return refs
    }

    /// Class-name entries: `u32 signature, 0x09 separator, zstring name`,
    /// packed back-to-back. Table ends at the section end, at a 0xFFFFFFFF
    /// sentinel, or when the separator byte is not 0x09 (0xFF tail padding)
    /// — the HKX2Library termination rule, matching probed files.
    private static func readClassNames(
        _ data: Data,
        section: HKXSectionHeader
    ) throws -> [HKXClassName] {
        var reader = BinaryReader(data, offset: section.dataStart)
        let end = section.dataStart + section.endOffset
        var entries: [HKXClassName] = []
        while reader.offset + 6 <= end {
            let entryStart = reader.offset
            let signature = try reader.readUInt32()
            if signature == 0xFFFF_FFFF {
                break
            }
            let separator = try reader.readUInt8()
            if separator != 0x09 {
                break
            }
            let name = try reader.readZString(encoding: .ascii)
            entries.append(HKXClassName(
                signature: signature,
                name: name,
                nameOffset: entryStart + 5 - section.dataStart
            ))
        }
        return entries
    }
}
