// Filesystem tests for the OpenSky native save container (issue #161).
//
// Every case works inside a unique directory under the system temporary
// directory and removes it again, so nothing here touches the real Application
// Support directory, the repo, or the game install. `defaultSavesDirectory` is
// exercised through a FileManager subclass that redirects the Application
// Support lookup into that same temporary directory, which keeps the test from
// creating a folder in the user's home just to read its name.

import Foundation
@testable import opensky
import Testing

/// Redirects `.applicationSupportDirectory` into a caller-owned directory.
private final class RedirectingFileManager: FileManager {
    let base: URL

    init(base: URL) {
        self.base = base
        super.init()
    }

    override func url(
        for directory: FileManager.SearchPathDirectory,
        in domain: FileManager.SearchPathDomainMask,
        appropriateFor url: URL?,
        create shouldCreate: Bool
    ) throws -> URL {
        guard directory == .applicationSupportDirectory else {
            return try super.url(
                for: directory,
                in: domain,
                appropriateFor: url,
                create: shouldCreate
            )
        }
        if shouldCreate {
            try createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }
}

struct OpenSkySaveIOTests {
    // MARK: - Scratch space

    /// A fresh directory per call; the caller removes it when it is done.
    private func makeScratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "opensky-save-io-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func remove(_ directory: URL) {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path(percentEncoded: false)
        )
        try? FileManager.default.removeItem(at: directory)
    }

    /// Everything in `directory`, dotfiles included, so a leftover temp file
    /// cannot hide behind its leading dot.
    private func contents(of directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        )
        .map(\.lastPathComponent)
        .sorted()
    }

    // MARK: - Writing

    @Test func writingCreatesTheFileWithExactlyTheGivenBytes() throws {
        let directory = try makeScratchDirectory()
        defer { remove(directory) }
        let destination = directory.appending(path: "quicksave.osav", directoryHint: .notDirectory)
        let save = OpenSkySaveFixture.encodedRichSave()

        try OpenSkySaveIO.writeAtomically(save, to: destination)

        let written = try Data(contentsOf: destination)
        #expect(written == save)
        #expect(try contents(of: directory) == ["quicksave.osav"])
        // The bytes on disk are a save, not just the right length.
        let decoded = try OpenSkySaveDecoder.decode(written)
        #expect(decoded.snapshot == OpenSkySaveFixture.richSnapshot())
    }

    @Test func overwritingReplacesTheContentsEntirely() throws {
        let directory = try makeScratchDirectory()
        defer { remove(directory) }
        let destination = directory.appending(path: "save.osav", directoryHint: .notDirectory)
        let long = Data(repeating: 0xAB, count: 4096)
        let short = Data(repeating: 0xCD, count: 7)

        try OpenSkySaveIO.writeAtomically(long, to: destination)
        let afterFirst = try Data(contentsOf: destination)
        #expect(afterFirst == long)
        try OpenSkySaveIO.writeAtomically(short, to: destination)

        // A shorter second write must truncate rather than leave a tail of the
        // first one behind.
        let afterSecond = try Data(contentsOf: destination)
        #expect(afterSecond == short)
        #expect(try contents(of: directory) == ["save.osav"])
    }

    @Test func writingAnEmptyPayloadIsStillAWholeFile() throws {
        let directory = try makeScratchDirectory()
        defer { remove(directory) }
        let destination = directory.appending(path: "empty.osav", directoryHint: .notDirectory)

        try OpenSkySaveIO.writeAtomically(Data(), to: destination)

        let written = try Data(contentsOf: destination)
        #expect(written.isEmpty)
        #expect(try contents(of: directory) == ["empty.osav"])
    }

    @Test func aSuccessfulWriteLeavesNoTemporaryFiles() throws {
        let directory = try makeScratchDirectory()
        defer { remove(directory) }
        for index in 0 ..< 5 {
            let destination = directory.appending(
                path: "save\(index).osav",
                directoryHint: .notDirectory
            )
            try OpenSkySaveIO.writeAtomically(Data([UInt8(index)]), to: destination)
        }
        #expect(try contents(of: directory).count == 5)
        #expect(try contents(of: directory).allSatisfy { $0.hasSuffix(".osav") })
    }

    // MARK: - Failure paths

    @Test func writingIntoAMissingDirectoryThrowsAndLeavesNothingBehind() throws {
        let directory = try makeScratchDirectory()
        defer { remove(directory) }
        let missing = directory.appending(path: "nope", directoryHint: .isDirectory)
        let destination = missing.appending(path: "save.osav", directoryHint: .notDirectory)

        #expect(throws: (any Error).self) {
            try OpenSkySaveIO.writeAtomically(Data([1, 2, 3]), to: destination)
        }
        #expect(FileManager.default
            .fileExists(atPath: missing.path(percentEncoded: false)) == false)
        #expect(try contents(of: directory).isEmpty)
    }

    @Test func aFailedWriteLeavesThePreviousSaveIntact() throws {
        // A directory with no write bit is still writable by root, so skip
        // rather than report a false pass when the tests run elevated.
        guard getuid() != 0 else { return }
        let directory = try makeScratchDirectory()
        defer { remove(directory) }
        let destination = directory.appending(path: "save.osav", directoryHint: .notDirectory)
        let original = OpenSkySaveFixture.encodedRichSave()
        try OpenSkySaveIO.writeAtomically(original, to: destination)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: directory.path(percentEncoded: false)
        )
        #expect(throws: (any Error).self) {
            try OpenSkySaveIO.writeAtomically(Data(repeating: 0xFF, count: 64), to: destination)
        }

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path(percentEncoded: false)
        )
        let survivor = try Data(contentsOf: destination)
        #expect(survivor == original)
        #expect(try contents(of: directory) == ["save.osav"])
    }

    // MARK: - Default location

    @Test func theDefaultSavesDirectoryEndsInOpenSkySaves() throws {
        let directory = try makeScratchDirectory()
        defer { remove(directory) }
        let base = directory.appending(path: "Application Support", directoryHint: .isDirectory)
        let fileManager = RedirectingFileManager(base: base)

        let saves = try OpenSkySaveIO.defaultSavesDirectory(fileManager: fileManager)

        #expect(Array(saves.pathComponents.suffix(2)) == ["OpenSky", "Saves"])
        #expect(saves.path(percentEncoded: false)
            .hasPrefix(base.path(percentEncoded: false)))
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: saves.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        #expect(exists)
        #expect(isDirectory.boolValue)
    }

    @Test func theDefaultSavesDirectoryIsStableAcrossCalls() throws {
        let directory = try makeScratchDirectory()
        defer { remove(directory) }
        let fileManager = RedirectingFileManager(
            base: directory.appending(path: "Application Support", directoryHint: .isDirectory)
        )
        let first = try OpenSkySaveIO.defaultSavesDirectory(fileManager: fileManager)
        let second = try OpenSkySaveIO.defaultSavesDirectory(fileManager: fileManager)
        #expect(first == second)

        // A save written into it round-trips, which is the whole point of the
        // directory existing.
        let destination = first.appending(path: "auto.osav", directoryHint: .notDirectory)
        let save = OpenSkySaveFixture.encodedRichSave()
        try OpenSkySaveIO.writeAtomically(save, to: destination)
        let reloaded = try OpenSkySaveDecoder.decode(Data(contentsOf: destination))
        #expect(reloaded.fingerprint == OpenSkySaveFixture.fingerprint)
    }
}
