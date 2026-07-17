// Unit tests for the VFS lookup layer. Fixtures: temp directory trees +
// synthetic BSA blobs built in code (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

struct VirtualFileSystemTests {
    /// Temp data root; each test writes its own loose files and archives.
    private let dataURL: URL

    init() throws {
        dataURL = FileManager.default.temporaryDirectory
            .appending(path: "opensky-vfs-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
    }

    private func writeArchive(named name: String, files: [BSAFixture.File]) throws -> URL {
        var fixture = BSAFixture()
        fixture.files = files
        let url = dataURL.appending(path: name, directoryHint: .notDirectory)
        try fixture.build().write(to: url)
        return url
    }

    private func writeLooseFile(_ relativePath: String, _ contents: String) throws {
        let url = dataURL.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }

    @Test func looseFileOverridesArchives() throws {
        let archive = try writeArchive(named: "base.bsa", files: [
            .init(folder: "meshes\\clutter", name: "cup.nif", stored: Data("archive".utf8))
        ])
        try writeLooseFile("Meshes/Clutter/Cup.nif", "loose")
        let vfs = VirtualFileSystem(dataURL: dataURL, archiveURLs: [archive])

        #expect(try vfs.contents(forPath: "meshes\\clutter\\cup.nif") == Data("loose".utf8))
    }

    @Test func laterArchiveWinsOverEarlier() throws {
        let base = try writeArchive(named: "base.bsa", files: [
            .init(folder: "textures", name: "a.dds", stored: Data("base".utf8)),
            .init(folder: "textures", name: "only-base.dds", stored: Data("unshadowed".utf8))
        ])
        let patch = try writeArchive(named: "patch.bsa", files: [
            .init(folder: "textures", name: "a.dds", stored: Data("patch".utf8))
        ])
        let vfs = VirtualFileSystem(dataURL: dataURL, archiveURLs: [base, patch])

        #expect(try vfs.contents(forPath: "textures\\a.dds") == Data("patch".utf8))
        #expect(try vfs.contents(forPath: "textures\\only-base.dds") == Data("unshadowed".utf8))
    }

    @Test func lookupIsCaseAndSeparatorInsensitive() throws {
        let archive = try writeArchive(named: "base.bsa", files: [
            .init(folder: "meshes\\clutter", name: "cup.nif", stored: Data("mesh".utf8))
        ])
        try writeLooseFile("Textures/Sky/Night.dds", "stars")
        let vfs = VirtualFileSystem(dataURL: dataURL, archiveURLs: [archive])

        #expect(try vfs.contents(forPath: "MESHES/Clutter\\CUP.NIF") == Data("mesh".utf8))
        #expect(try vfs.contents(forPath: "textures\\sky\\night.dds") == Data("stars".utf8))
        #expect(vfs.exists("Meshes\\CLUTTER/cup.nif"))
    }

    @Test func missingFileThrowsNotFound() throws {
        let vfs = VirtualFileSystem(dataURL: dataURL, archiveURLs: [])

        #expect(!vfs.exists("meshes\\nope.nif"))
        #expect(throws: VFSError.fileNotFound(path: "meshes\\nope.nif")) {
            _ = try vfs.contents(forPath: "meshes/nope.nif")
        }
    }

    @Test func pathsEscapingDataRootAreRejected() throws {
        try writeLooseFile("meshes/cup.nif", "mesh")
        let vfs = VirtualFileSystem(dataURL: dataURL, archiveURLs: [])

        #expect(throws: VFSError.invalidPath("..\\secrets.txt")) {
            _ = try vfs.contents(forPath: "..\\secrets.txt")
        }
        #expect(throws: VFSError.invalidPath("")) {
            _ = try vfs.contents(forPath: "")
        }
        #expect(!vfs.exists("meshes\\..\\meshes\\cup.nif"))
    }

    @Test func malformedAndMissingArchivesAreSkippedNotFatal() throws {
        let corrupt = dataURL.appending(path: "corrupt.bsa", directoryHint: .notDirectory)
        try Data("this is not a BSA archive".utf8).write(to: corrupt)
        let absent = dataURL.appending(path: "absent.bsa", directoryHint: .notDirectory)
        let good = try writeArchive(named: "good.bsa", files: [
            .init(folder: "sounds", name: "hit.wav", stored: Data("thud".utf8))
        ])
        // Highest priority slots are broken; lookup must fall through to good.
        let vfs = VirtualFileSystem(dataURL: dataURL, archiveURLs: [good, corrupt, absent])

        #expect(try vfs.contents(forPath: "sounds\\hit.wav") == Data("thud".utf8))
    }

    @Test func archiveEntriesReportsWinningArchivePerPath() throws {
        let base = try writeArchive(named: "base.bsa", files: [
            .init(folder: "textures", name: "a.dds", stored: Data("base".utf8)),
            .init(folder: "meshes", name: "m.nif", stored: Data("mesh".utf8))
        ])
        let patch = try writeArchive(named: "patch.bsa", files: [
            .init(folder: "textures", name: "a.dds", stored: Data("patch".utf8))
        ])
        let vfs = VirtualFileSystem(dataURL: dataURL, archiveURLs: [base, patch])

        // Sorted by path; the shared path is attributed to the later-opened
        // (higher-priority) archive, matching contents(forPath:).
        #expect(vfs.archiveEntries() == [
            VFSEntry(path: "meshes\\m.nif", archive: "base.bsa"),
            VFSEntry(path: "textures\\a.dds", archive: "patch.bsa")
        ])
    }

    @Test func normalizeCanonicalizesSeparatorsAndCase() throws {
        #expect(try VirtualFileSystem.normalize("Meshes//Clutter\\CUP.nif")
            == "meshes\\clutter\\cup.nif")
        #expect(try VirtualFileSystem.normalize("\\textures\\a.dds") == "textures\\a.dds")
        #expect(throws: VFSError.invalidPath("a\\.\\b")) {
            _ = try VirtualFileSystem.normalize("a\\.\\b")
        }
    }
}
