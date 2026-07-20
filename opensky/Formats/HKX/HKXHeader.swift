// Havok packfile header (todo 6.1). Havok ships no public spec; layout is
// reimplemented from community documentation (hkxcmd/ck-cmd notes, NifTools
// skeleton discussions) and verified byte-by-byte by probe against SSE
// `skeleton.hkx` + idle `.hkx` files — all observed files are 64-bit
// little-endian "hk_2010.2.0-r1" packfiles, fileVersion 8, 3 sections.
// docs/formats/hkx-container.md records the observed layout.

import Foundation

nonisolated enum HKXError: Error, Equatable {
    /// First two u32s are not the packfile magic pair.
    case badMagic(found0: UInt32, found1: UInt32)
    /// Layout rules the engine does not support (SSE files are 8-byte
    /// pointer, little-endian).
    case unsupportedLayout(pointerSize: UInt8, littleEndian: UInt8)
    /// Section count missing or absurd for a packfile.
    case sectionCountOutOfRange(UInt32)
    /// Section data range does not fit the file.
    case sectionOutOfBounds(name: String, start: Int, end: Int, fileSize: Int)
    /// Fixup offsets not ascending within the section payload.
    case fixupRangeInvalid(section: String)
    /// Header index does not name an existing section.
    case sectionIndexInvalid(Int)
}

/// Packfile header, 64 bytes at offset 0. All integers little-endian.
nonisolated struct HKXHeader {
    static let magic0: UInt32 = 0x57E0_E057
    static let magic1: UInt32 = 0x10C0_C010
    /// Observed on every SSE file probed; other versions may parse but are
    /// flagged by callers, not rejected here.
    static let expectedVersionString = "hk_2010.2.0-r1"

    let userTag: UInt32
    let fileVersion: UInt32
    /// Layout rules, 4 bytes: pointer size, endianness, padding reuse,
    /// empty-base-class optimization. SSE: 8 / 1 / 0 / 1.
    let pointerSize: UInt8
    let isLittleEndian: Bool
    let reusePaddingOptimization: Bool
    let emptyBaseClassOptimization: Bool
    let sectionCount: Int
    /// Section holding the top-level object (SSE: 2 -> `__data__`) and the
    /// object's offset inside it (SSE: 0).
    let contentsSectionIndex: Int
    let contentsSectionOffset: Int
    /// Section + offset of the top-level object's class-name string
    /// (SSE: `__classnames__` offset of "hkRootLevelContainer").
    let contentsClassNameSectionIndex: Int
    let contentsClassNameOffset: Int
    /// Null-terminated inside a 16-byte 0xFF-padded field.
    let versionString: String
    let flags: UInt32

    init(reader: inout BinaryReader) throws {
        let magic0 = try reader.readUInt32()
        let magic1 = try reader.readUInt32()
        guard magic0 == Self.magic0, magic1 == Self.magic1 else {
            throw HKXError.badMagic(found0: magic0, found1: magic1)
        }
        userTag = try reader.readUInt32()
        fileVersion = try reader.readUInt32()
        let pointerSize = try reader.readUInt8()
        let littleEndian = try reader.readUInt8()
        guard pointerSize == 8, littleEndian == 1 else {
            throw HKXError.unsupportedLayout(
                pointerSize: pointerSize,
                littleEndian: littleEndian
            )
        }
        self.pointerSize = pointerSize
        isLittleEndian = true
        reusePaddingOptimization = try reader.readUInt8() != 0
        emptyBaseClassOptimization = try reader.readUInt8() != 0
        let sectionCount = try reader.readUInt32()
        // Defensive bound: vanilla files carry 3; anything huge is garbage,
        // not a real packfile.
        guard (1 ... 64).contains(sectionCount) else {
            throw HKXError.sectionCountOutOfRange(sectionCount)
        }
        self.sectionCount = Int(sectionCount)
        contentsSectionIndex = try Int(reader.readUInt32())
        contentsSectionOffset = try Int(reader.readUInt32())
        contentsClassNameSectionIndex = try Int(reader.readUInt32())
        contentsClassNameOffset = try Int(reader.readUInt32())
        // 16-byte field, name null-terminated, remainder 0xFF padding.
        let versionFieldOffset = reader.offset
        let versionField = try reader.read(count: 16)
        let nameBytes = versionField.prefix { $0 != 0 }
        guard let version = String(bytes: nameBytes, encoding: .ascii) else {
            throw BinaryReaderError.invalidString(offset: versionFieldOffset)
        }
        versionString = version
        flags = try reader.readUInt32()
        reader.skip(4) // pad, observed 0xFFFFFFFF
    }
}
