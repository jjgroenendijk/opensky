// Unit tests for the BSA v105 parser. Fixtures are synthetic archives built
// in code via BSAFixture — never extracted game files (AGENTS.md "Legal & IP
// boundary").

import Foundation
@testable import OpenSkyFormatsCore
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
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
        #expect(archive.entry(forNormalizedPath: "meshes\\clutter\\cup.nif")?.path == entry.path)
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

    @Test func theHeaderAloneIsCheckedWithoutTheTables() throws {
        var fixture = BSAFixture()
        fixture.files = [BSAFixture.File(folder: "meshes", name: "a.nif", stored: Data([1, 2]))]
        let data = fixture.build()
        try BSAArchive.validateHeader(data.prefix(BSAArchive.headerSize))
        #expect(throws: BSAError.notABSA) {
            try BSAArchive.validateHeader(Data("NOPE".utf8) + data.dropFirst(4).prefix(32))
        }
        #expect(throws: BSAError.malformed("header shorter than 36 bytes")) {
            try BSAArchive.validateHeader(data.prefix(20))
        }
    }
}
