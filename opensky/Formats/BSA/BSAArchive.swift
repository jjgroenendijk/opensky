// Skyrim SE BSA (v105) archive reader. Parses the header and folder/file
// tables eagerly (small), extracts file payloads lazily on demand.
//
// Reference: UESP "Skyrim Mod:Archive File Format"
//   https://en.uesp.net/wiki/Skyrim_Mod:Archive_File_Format
// Layout documented in docs/formats/bsa.md.

import Foundation

nonisolated enum BSAError: Error, Equatable {
    case notABSA
    case unsupportedVersion(UInt32)
    case missingNames
    case malformed(String)
    case entryNotFound(String)
    case sizeMismatch(expected: Int, actual: Int)
}

nonisolated struct BSAArchive {
    struct ArchiveFlags: OptionSet {
        let rawValue: UInt32

        static let includeFolderNames = ArchiveFlags(rawValue: 1 << 0)
        static let includeFileNames = ArchiveFlags(rawValue: 1 << 1)
        static let compressedByDefault = ArchiveFlags(rawValue: 1 << 2)
        static let embeddedFileNames = ArchiveFlags(rawValue: 1 << 8)
    }

    struct Entry {
        let folder: String
        let name: String
        /// Full lowercase path with backslash separators, as the game refers to files.
        var path: String {
            folder.isEmpty ? name : "\(folder)\\\(name)"
        }

        let offset: UInt32
        let packedSize: UInt32
        let isCompressed: Bool
    }

    static let supportedVersion: UInt32 = 105

    let flags: ArchiveFlags
    let entries: [Entry]
    private let data: Data
    private let entriesByPath: [String: Int]

    /// Memory-maps the archive; nothing beyond the tables is read up front.
    init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    init(data: Data) throws {
        self.data = data
        var reader = BinaryReader(data)

        let header = try Self.readHeader(&reader)
        flags = header.flags

        reader.seek(to: header.folderRecordOffset)
        let folders = try (0 ..< header.folderCount).map { _ in
            try FolderRecord(reader: &reader)
        }
        let blocks = try Self.readFileRecordBlocks(
            folders: folders,
            totalFileNameLength: header.totalFileNameLength,
            reader: &reader
        )

        // File name block follows the last file record block.
        var names: [String] = []
        names.reserveCapacity(header.fileCount)
        for _ in 0 ..< header.fileCount {
            try names.append(reader.readZString().lowercased())
        }

        entries = try Self.makeEntries(blocks: blocks, names: names, flags: flags)
        entriesByPath = Dictionary(
            entries.enumerated().map { ($0.element.path, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private struct Header {
        let flags: ArchiveFlags
        let folderRecordOffset: Int
        let folderCount: Int
        let fileCount: Int
        let totalFileNameLength: Int
    }

    private static func readHeader(_ reader: inout BinaryReader) throws -> Header {
        guard let magic = try? reader.read(count: 4), magic == Data("BSA\0".utf8) else {
            throw BSAError.notABSA
        }
        let version = try reader.readUInt32()
        guard version == supportedVersion else {
            throw BSAError.unsupportedVersion(version)
        }
        let folderRecordOffset = try Int(reader.readUInt32())
        let flags = try ArchiveFlags(rawValue: reader.readUInt32())
        let folderCount = try Int(reader.readUInt32())
        let fileCount = try Int(reader.readUInt32())
        _ = try reader.readUInt32() // totalFolderNameLength
        let totalFileNameLength = try Int(reader.readUInt32())
        _ = try reader.readUInt32() // fileFlags (content-type hints, unused)

        // Name-hash lookup is not implemented; we key entries by their names.
        guard flags.contains(.includeFolderNames), flags.contains(.includeFileNames) else {
            throw BSAError.missingNames
        }
        return Header(
            flags: flags,
            folderRecordOffset: folderRecordOffset,
            folderCount: folderCount,
            fileCount: fileCount,
            totalFileNameLength: totalFileNameLength
        )
    }

    /// Per folder: bzstring name + 16-byte file records. The stored folder
    /// offset includes totalFileNameLength (format quirk, see docs).
    private static func readFileRecordBlocks(
        folders: [FolderRecord],
        totalFileNameLength: Int,
        reader: inout BinaryReader
    ) throws -> [(folder: String, records: [FileRecord])] {
        var blocks: [(folder: String, records: [FileRecord])] = []
        blocks.reserveCapacity(folders.count)
        for folder in folders {
            let blockOffset = Int(folder.offset) - totalFileNameLength
            guard blockOffset >= 0, blockOffset <= reader.data.count else {
                throw BSAError.malformed("folder block offset out of range")
            }
            reader.seek(to: blockOffset)
            let name = try reader.readBZString()
            let records = try (0 ..< folder.fileCount).map { _ in
                try FileRecord(reader: &reader)
            }
            blocks.append((name.lowercased(), records))
        }
        return blocks
    }

    private static func makeEntries(
        blocks: [(folder: String, records: [FileRecord])],
        names: [String],
        flags: ArchiveFlags
    ) throws -> [Entry] {
        var entries: [Entry] = []
        entries.reserveCapacity(names.count)
        var nameIndex = 0
        let compressedDefault = flags.contains(.compressedByDefault)
        for (folderName, records) in blocks {
            for record in records {
                guard nameIndex < names.count else {
                    throw BSAError.malformed("more file records than file names")
                }
                // Bit 30 of size toggles the archive's default compression.
                let toggled = record.size & 0x4000_0000 != 0
                entries.append(
                    Entry(
                        folder: folderName,
                        name: names[nameIndex],
                        offset: record.offset,
                        packedSize: record.size & 0x3FFF_FFFF,
                        isCompressed: compressedDefault != toggled
                    )
                )
                nameIndex += 1
            }
        }
        return entries
    }

    /// Case-insensitive lookup; accepts `/` or `\` separators.
    func entry(forPath path: String) -> Entry? {
        let key = path.lowercased().replacingOccurrences(of: "/", with: "\\")
        return entriesByPath[key].map { entries[$0] }
    }

    /// Extracts and (if needed) decompresses one file's payload.
    func contents(of entry: Entry) throws -> Data {
        var reader = BinaryReader(data, offset: Int(entry.offset))
        var remaining = Int(entry.packedSize)

        if flags.contains(.embeddedFileNames) {
            let before = reader.offset
            _ = try reader.readBString()
            remaining -= reader.offset - before
        }

        guard remaining >= 0 else { throw BSAError.malformed("packed size underflow") }
        guard entry.isCompressed else {
            return try reader.read(count: remaining)
        }

        let decompressedSize = try Int(reader.readUInt32())
        remaining -= 4
        let payload = try reader.read(count: remaining)
        let result = try LZ4.decompressFrame(payload, sizeLimit: decompressedSize)
        guard result.count == decompressedSize else {
            throw BSAError.sizeMismatch(expected: decompressedSize, actual: result.count)
        }
        return result
    }

    /// 24-byte v105 folder record.
    private struct FolderRecord {
        let nameHash: UInt64
        let fileCount: Int
        let offset: UInt64

        init(reader: inout BinaryReader) throws {
            nameHash = try reader.readUInt64()
            fileCount = try Int(reader.readUInt32())
            _ = try reader.readUInt32() // padding
            offset = try reader.readUInt64()
        }
    }

    /// 16-byte file record.
    private struct FileRecord {
        let nameHash: UInt64
        let size: UInt32
        let offset: UInt32

        init(reader: inout BinaryReader) throws {
            nameHash = try reader.readUInt64()
            size = try reader.readUInt32()
            offset = try reader.readUInt32()
        }
    }
}
