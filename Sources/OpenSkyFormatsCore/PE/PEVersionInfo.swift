// The file version stamped in a Windows executable's version resource. The
// launcher reads it to show which game build the install is. Layout:
// docs/formats/pe-version.md.

import Foundation

nonisolated public enum PEVersionError: Error, Equatable, Sendable {
    case notAnExecutable
    case noResourceSection
    case noVersionResource
    case malformed(String)
}

/// A four-part file version, such as `1.6.1170.0`.
nonisolated public struct PEFileVersion: Equatable, Comparable, Sendable, CustomStringConvertible {
    public let parts: [UInt16]

    public init(_ major: UInt16, _ minor: UInt16, _ build: UInt16, _ revision: UInt16) {
        parts = [major, minor, build, revision]
    }

    public var description: String {
        parts.map(String.init).joined(separator: ".")
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.parts.lexicographicallyPrecedes(rhs.parts)
    }
}

nonisolated public enum PEVersionInfo {
    static let resourceTypeVersion: UInt32 = 16
    static let fixedInfoSignature: UInt32 = 0xFEEF_04BD
    private static let subdirectoryBit: UInt32 = 0x8000_0000

    private struct Section {
        let virtualAddress: Int
        let rawSize: Int
        let rawOffset: Int
    }

    /// Maps the file, so only the headers and the resource pages are read.
    public static func fileVersion(url: URL) throws -> PEFileVersion {
        try fileVersion(data: Data(contentsOf: url, options: .alwaysMapped))
    }

    public static func fileVersion(data: Data) throws -> PEFileVersion {
        do {
            let resources = try resourceSection(data)
            let entry = try versionDataOffset(data, section: resources)
            return try fixedFileVersion(data, at: entry)
        } catch is BinaryReaderError {
            throw PEVersionError.malformed("truncated header")
        }
    }

    private static func resourceSection(_ data: Data) throws -> Section {
        var reader = BinaryReader(data)
        guard try reader.read(count: 2) == Data("MZ".utf8) else {
            throw PEVersionError.notAnExecutable
        }
        reader.seek(to: 0x3C)
        let peOffset = try Int(reader.readUInt32())
        reader.seek(to: peOffset)
        guard try reader.read(count: 4) == Data([0x50, 0x45, 0, 0]) else {
            throw PEVersionError.notAnExecutable
        }
        reader.skip(2)
        let sectionCount = try Int(reader.readUInt16())
        reader.skip(12)
        let optionalHeaderSize = try Int(reader.readUInt16())
        reader.skip(2 + optionalHeaderSize)
        for _ in 0 ..< sectionCount {
            let name = try reader.read(count: 8)
            reader.skip(4)
            let virtualAddress = try Int(reader.readUInt32())
            let rawSize = try Int(reader.readUInt32())
            let rawOffset = try Int(reader.readUInt32())
            reader.skip(16)
            if name.prefix(while: { $0 != 0 }) == Data(".rsrc".utf8) {
                return Section(
                    virtualAddress: virtualAddress,
                    rawSize: rawSize,
                    rawOffset: rawOffset
                )
            }
        }
        throw PEVersionError.noResourceSection
    }

    /// Walks type, name, and language levels to the first version data entry.
    private static func versionDataOffset(_ data: Data, section: Section) throws -> Int {
        var directory = 0
        for level in 0 ..< 3 {
            var reader = BinaryReader(data, offset: section.rawOffset + directory + 12)
            let count = try Int(reader.readUInt16()) + Int(reader.readUInt16())
            var next: UInt32?
            for _ in 0 ..< count {
                let id = try reader.readUInt32()
                let target = try reader.readUInt32()
                if level == 0, id != resourceTypeVersion {
                    continue
                }
                next = target
                break
            }
            guard let next else { throw PEVersionError.noVersionResource }
            let offset = Int(next & ~subdirectoryBit)
            guard offset < section.rawSize else {
                throw PEVersionError.malformed("resource entry outside the section")
            }
            if next & subdirectoryBit == 0 {
                var entry = BinaryReader(data, offset: section.rawOffset + offset)
                let rva = try Int(entry.readUInt32())
                return rva - section.virtualAddress + section.rawOffset
            }
            directory = offset
        }
        throw PEVersionError.malformed("resource tree deeper than three levels")
    }

    /// `VS_VERSIONINFO`: three `UInt16`s, the UTF-16 key, padding to four bytes,
    /// then `VS_FIXEDFILEINFO`.
    private static func fixedFileVersion(_ data: Data, at offset: Int) throws -> PEFileVersion {
        var reader = BinaryReader(data, offset: offset + 6)
        while try reader.readUInt16() != 0 {}
        let aligned = (reader.offset + 3) & ~3
        reader.seek(to: aligned)
        guard try reader.readUInt32() == fixedInfoSignature else {
            throw PEVersionError.malformed("no VS_FIXEDFILEINFO signature")
        }
        reader.skip(4)
        let high = try reader.readUInt32()
        let low = try reader.readUInt32()
        return PEFileVersion(
            UInt16(high >> 16), UInt16(high & 0xFFFF), UInt16(low >> 16), UInt16(low & 0xFFFF)
        )
    }
}
