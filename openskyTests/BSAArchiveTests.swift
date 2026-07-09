// Unit tests for the BSA v105 parser. Fixtures are synthetic archives built
// in code — never extracted game files (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

/// Builds a minimal spec-conformant BSA v105 byte blob.
private struct BSAFixture {
    struct File {
        let folder: String
        let name: String
        /// Bytes stored in the data area, verbatim.
        let stored: Data
        /// Toggle bit 30 of the size field (inverts archive default compression).
        var toggleCompression = false
    }

    var flags: UInt32 = 0x3 // folder + file names present
    var files: [File] = []

    func build() -> Data {
        // Preserve first-seen folder order.
        var folders: [(name: String, files: [File])] = []
        for file in files {
            if let index = folders.firstIndex(where: { $0.name == file.folder }) {
                folders[index].files.append(file)
            } else {
                folders.append((file.folder, [file]))
            }
        }

        let headerSize = 36
        let folderRecordsSize = folders.count * 24
        let blocksSize = folders.reduce(0) { $0 + 2 + $1.name.count + 16 * $1.files.count }
        let namesSize = files.reduce(0) { $0 + $1.name.count + 1 }
        let totalFolderNameLength = folders.reduce(0) { $0 + $1.name.count + 1 }
        var dataOffset = headerSize + folderRecordsSize + blocksSize + namesSize

        var header = Data("BSA\0".utf8)
        header.appendUInt32(105)
        header.appendUInt32(UInt32(headerSize))
        header.appendUInt32(flags)
        header.appendUInt32(UInt32(folders.count))
        header.appendUInt32(UInt32(files.count))
        header.appendUInt32(UInt32(totalFolderNameLength))
        header.appendUInt32(UInt32(namesSize))
        header.appendUInt32(0) // fileFlags

        var records = Data()
        var blocks = Data()
        var names = Data()
        var payloads = Data()
        var blockOffset = headerSize + folderRecordsSize
        for (name, folderFiles) in folders {
            records.appendUInt64(0) // name hash — parser keys by names
            records.appendUInt32(UInt32(folderFiles.count))
            records.appendUInt32(0) // padding
            // Stored offset includes totalFileNameLength (format quirk).
            records.appendUInt64(UInt64(blockOffset + namesSize))

            blocks.append(UInt8(name.count + 1))
            blocks.append(Data(name.utf8))
            blocks.append(0)
            for file in folderFiles {
                var size = UInt32(file.stored.count)
                if file.toggleCompression { size |= 0x4000_0000 }
                blocks.appendUInt64(0) // name hash
                blocks.appendUInt32(size)
                blocks.appendUInt32(UInt32(dataOffset))
                payloads.append(file.stored)
                dataOffset += file.stored.count
                names.append(Data(file.name.utf8))
                names.append(0)
            }
            blockOffset += 2 + name.count + 16 * folderFiles.count
        }
        return header + records + blocks + names + payloads
    }
}

extension Data {
    fileprivate mutating func appendUInt32(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    fileprivate mutating func appendUInt64(_ value: UInt64) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}

struct BSAArchiveTests {
    // Same hand-assembled LZ4 vector as LZ4Tests: "abcdabcdabcdXYZQW".
    private static let lz4Plain = Data("abcdabcdabcdXYZQW".utf8)
    private static var lz4Stored: Data {
        var stored = Data()
        stored.appendUInt32(UInt32(lz4Plain.count)) // decompressed size prefix
        stored.append(contentsOf: [0x04, 0x22, 0x4D, 0x18, 0x40, 0x40, 0x00]) // frame header
        let block = Data([0x44]) + Data("abcd".utf8) + Data([0x04, 0x00, 0x50]) + Data("XYZQW".utf8)
        stored.appendUInt32(UInt32(block.count))
        stored.append(block)
        stored.append(contentsOf: [0, 0, 0, 0]) // EndMark
        return stored
    }

    @Test func parsesAndExtractsUncompressed() throws {
        var fixture = BSAFixture()
        fixture.files = [
            .init(folder: "meshes\\clutter", name: "cup.nif", stored: Data("mesh-bytes".utf8)),
            .init(folder: "meshes\\clutter", name: "plate.nif", stored: Data("plate!".utf8)),
            .init(folder: "textures", name: "cup.dds", stored: Data("texture-bytes".utf8))
        ]
        let archive = try BSAArchive(data: fixture.build())

        #expect(archive.entries.count == 3)
        #expect(archive.entries.map(\.path) == [
            "meshes\\clutter\\cup.nif",
            "meshes\\clutter\\plate.nif",
            "textures\\cup.dds"
        ])
        let entry = try #require(archive.entry(forPath: "MESHES/Clutter/Cup.nif"))
        #expect(try archive.contents(of: entry) == Data("mesh-bytes".utf8))
    }

    @Test func extractsLZ4CompressedFile() throws {
        var fixture = BSAFixture()
        fixture.flags = 0x3 | 0x4 // compressed by default
        fixture.files = [.init(folder: "scripts", name: "a.pex", stored: Self.lz4Stored)]
        let archive = try BSAArchive(data: fixture.build())

        let entry = try #require(archive.entry(forPath: "scripts\\a.pex"))
        #expect(entry.isCompressed)
        #expect(try archive.contents(of: entry) == Self.lz4Plain)
    }

    @Test func compressionToggleBitInvertsDefault() throws {
        var fixture = BSAFixture()
        fixture.flags = 0x3 | 0x4 // compressed by default...
        fixture.files = [ // ...but bit 30 marks this file uncompressed
            .init(folder: "f", name: "raw.bin", stored: Data("raw".utf8), toggleCompression: true)
        ]
        let archive = try BSAArchive(data: fixture.build())

        let entry = try #require(archive.entry(forPath: "f\\raw.bin"))
        #expect(!entry.isCompressed)
        #expect(try archive.contents(of: entry) == Data("raw".utf8))
    }

    @Test func embeddedFileNamePrefixIsSkipped() throws {
        var fixture = BSAFixture()
        fixture.flags = 0x3 | 0x100
        let stored = Data([9]) + Data("f\\emb.bin".utf8) + Data("payload".utf8)
        fixture.files = [.init(folder: "f", name: "emb.bin", stored: stored)]
        let archive = try BSAArchive(data: fixture.build())

        let entry = try #require(archive.entry(forPath: "f\\emb.bin"))
        #expect(try archive.contents(of: entry) == Data("payload".utf8))
    }

    @Test func rejectsWrongMagicAndVersion() {
        #expect(throws: BSAError.notABSA) {
            _ = try BSAArchive(data: Data("NOPE".utf8) + Data(count: 64))
        }
        var fixture = BSAFixture()
        fixture.files = [.init(folder: "f", name: "a", stored: Data())]
        var bytes = fixture.build()
        bytes[4] = 104 // Skyrim LE version
        #expect(throws: BSAError.unsupportedVersion(104)) {
            _ = try BSAArchive(data: bytes)
        }
    }

    @Test func rejectsTruncatedTables() throws {
        var fixture = BSAFixture()
        fixture.files = [.init(folder: "f", name: "a.bin", stored: Data("x".utf8))]
        let bytes = fixture.build()
        #expect(throws: (any Error).self) {
            _ = try BSAArchive(data: bytes.prefix(40))
        }
    }
}
