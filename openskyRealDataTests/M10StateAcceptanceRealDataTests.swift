// M10.1 acceptance against the user's read-only Skyrim SE install (issue #162):
// the real-data half of "world state saves and loads against the load order
// that is actually installed".
//
// The synthetic suite proves the round trip; what it cannot prove is that
// `OpenSkySaveStore.fingerprint(forRoot:)` reads the shipped plugins at all, or
// that a save written against them is refused once that load order changes.
// Both need real TES4 headers, so they live here.
//
// Deliberately light: only the TES4 record of each plugin in the load order is
// decoded, which is one small record at the head of a memory-mapped file. No
// world is loaded, no cell is built and no archive is opened.
//
// No game-derived bytes are written anywhere. The save goes to a temporary
// directory that is deleted at the end of the test, and it contains OpenSky's
// own synthetic snapshot plus the plugin names and HEDR stats needed to verify
// it; the report goes to gitignored `logs/`.

import Foundation
@testable import opensky
import Testing

struct M10StateAcceptanceRealDataTests {
    /// Env-gated exactly like `M9AudioAcceptanceRealDataTests`: without
    /// `OPENSKY_DATA_ROOT` the test skips instead of consulting the Steam
    /// default. No Metal device is needed — nothing here renders.
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    private static var canRun: Bool {
        dataRoot != nil
    }

    /// A save written against the installed load order round-trips through a
    /// real slot file and verifies against the fingerprint of the very same
    /// install it was written on.
    @Test(.enabled(if: Self.canRun))
    func savedStateRoundTripsAgainstTheInstalledLoadOrder() throws {
        let root = try #require(Self.dataRoot)
        let installed = try OpenSkySaveStore.fingerprint(forRoot: root)
        #expect(!installed.isEmpty, "the install resolves no plugins at all")
        #expect(
            installed.first?.name.lowercased() == "skyrim.esm",
            "the master plugin is not first in the resolved load order"
        )
        #expect(
            installed.allSatisfy { $0.recordCount > 0 },
            "a plugin's HEDR reports no records, so its header did not decode"
        )

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let saves = OpenSkySaveStore(directory: directory)
        let snapshot = OpenSkySaveFixture.richSnapshot()
        let written = try saves.save(
            snapshot: snapshot,
            fingerprint: installed,
            metadata: OpenSkySaveFixture.metadata,
            toSlot: Self.slot
        )
        #expect(FileManager.default.fileExists(atPath: written.path(percentEncoded: false)))

        let file = try saves.load(slot: Self.slot, verifyingAgainst: installed)
        #expect(file.snapshot == snapshot)
        #expect(file.fingerprint == installed)
        #expect(file.allocator.nextSequence == snapshot.nextGeneratedSequence)

        // Fingerprinting twice on an unchanged install has to agree, or the
        // check would reject the machine it was written on.
        let second = try OpenSkySaveStore.fingerprint(forRoot: root)
        #expect(second == installed)

        try Self.write("""
        [INFO] data root: \(root.dataURL.lastPathComponent) (source \(root.source))
        [INFO] load order: \(installed.count) plugins — \
        \(installed.map(\.name).joined(separator: ", "))
        [INFO] round trip: \(snapshot.dirtyCount) deltas written to slot \
        \(Self.slot) and read back identical, verified against the installed load order
        """)
    }

    /// A fingerprint that no longer matches the file is refused, and the error
    /// names the difference. This is the check that stops a save from being
    /// applied to a world its references no longer describe.
    @Test(.enabled(if: Self.canRun))
    func aChangedLoadOrderIsDetectedOnLoad() throws {
        let root = try #require(Self.dataRoot)
        let installed = try OpenSkySaveStore.fingerprint(forRoot: root)
        let first = try #require(installed.first)

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let saves = OpenSkySaveStore(directory: directory)
        try saves.save(
            snapshot: OpenSkySaveFixture.richSnapshot(),
            fingerprint: installed,
            metadata: OpenSkySaveFixture.metadata,
            toSlot: Self.slot
        )

        // An edited master: same name and position, one more record than the
        // file on disk has.
        var edited = installed
        edited[0] = SavePluginFingerprint(
            name: first.name,
            hedrVersion: first.hedrVersion,
            recordCount: first.recordCount + 1,
            nextObjectID: first.nextObjectID
        )
        #expect(throws: OpenSkySaveError.self) {
            try saves.load(slot: Self.slot, verifyingAgainst: edited)
        }

        // A plugin removed from the end of the load order.
        #expect(throws: OpenSkySaveError.self) {
            try saves.load(slot: Self.slot, verifyingAgainst: Array(installed.dropLast()))
        }

        // Decoding still works with no fingerprint at all, because reading a
        // save must not depend on the install being present.
        let file = try saves.load(slot: Self.slot)
        #expect(file.fingerprint == installed)
    }

    // MARK: - Support

    private static let slot = "m10-real-data-acceptance"

    private static func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "opensky-m10-real-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static var logs: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "logs")
    }

    private static func write(_ report: String) throws {
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try report.write(
            to: logs.appending(path: "m10-state-acceptance.log"),
            atomically: true,
            encoding: .utf8
        )
        print(report)
    }
}
