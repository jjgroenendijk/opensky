// Load-order fingerprint builder tests (issue #162, roadmap item 10.1.5).
//
// `OpenSkySaveFingerprintTests` covers verifying a fingerprint against an
// installed load order; this file covers building one in the first place.
// Plugins are synthetic TES4 bytes from ESMFixture written into a temporary
// directory laid out like an install root, so no game data is involved.

import Foundation
@testable import opensky
import Testing

struct OpenSkySaveStoreFingerprintTests {
    /// Install root with a `Data/` folder, removed again after `body`.
    private func withTemporaryInstall(_ body: (URL, URL) throws -> Void) throws {
        let install = FileManager.default.temporaryDirectory
            .appending(path: "opensky-install-\(UUID().uuidString)", directoryHint: .isDirectory)
        let data = install.appending(path: "Data", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: install) }
        try body(install, data)
    }

    @discardableResult
    private func writePlugin(_ name: String, in directory: URL) throws -> URL {
        let url = directory.appending(path: name, directoryHint: .notDirectory)
        try ESMFixture.tes4(author: "OpenSky test").write(to: url)
        return url
    }

    private func entry(_ name: String, in directory: URL) -> PluginLoadOrder.Entry {
        PluginLoadOrder.Entry(
            name: name,
            url: directory.appending(path: name, directoryHint: .notDirectory)
        )
    }

    @Test
    func fingerprintFollowsTheGivenOrderAndCarriesHEDRStats() throws {
        try withTemporaryInstall { _, data in
            for name in ["Skyrim.esm", "Dawnguard.esm"] {
                try writePlugin(name, in: data)
            }
            let entries = [entry("Skyrim.esm", in: data), entry("Dawnguard.esm", in: data)]

            let fingerprint = try OpenSkySaveStore.fingerprint(forPlugins: entries)

            #expect(fingerprint.map(\.name) == ["Skyrim.esm", "Dawnguard.esm"])
            // ESMFixture.tes4 writes HEDR version 1.71, zero records, next
            // object ID 0x800.
            #expect(fingerprint.allSatisfy { $0.hedrVersion == Float(1.71) })
            #expect(fingerprint.allSatisfy { $0.recordCount == 0 })
            #expect(fingerprint.allSatisfy { $0.nextObjectID == 0x800 })
        }
    }

    @Test
    func anEmptyLoadOrderProducesAnEmptyFingerprint() throws {
        #expect(try OpenSkySaveStore.fingerprint(forPlugins: []).isEmpty)
    }

    @Test
    func aMissingPluginThrowsRatherThanBeingSkipped() throws {
        try withTemporaryInstall { _, data in
            try writePlugin("Skyrim.esm", in: data)
            let entries = [entry("Skyrim.esm", in: data), entry("Absent.esp", in: data)]

            let thrown = #expect(throws: OpenSkySaveStoreError.self) {
                try OpenSkySaveStore.fingerprint(forPlugins: entries)
            }

            guard case let .unreadablePlugin(name, _)? = thrown else {
                Issue.record("expected unreadablePlugin, got \(String(describing: thrown))")
                return
            }
            #expect(name == "Absent.esp")
        }
    }

    @Test
    func aTruncatedPluginThrowsInsteadOfCrashing() throws {
        try withTemporaryInstall { _, data in
            let url = data.appending(path: "Broken.esp", directoryHint: .notDirectory)
            try Data(ESMFixture.tes4().prefix(12)).write(to: url)

            #expect(throws: OpenSkySaveStoreError.self) {
                try OpenSkySaveStore.fingerprint(
                    forPlugins: [PluginLoadOrder.Entry(name: "Broken.esp", url: url)]
                )
            }
        }
    }

    @Test
    func fingerprintForARootResolvesTheOfficialMasterOnDisk() throws {
        try withTemporaryInstall { install, data in
            try writePlugin("Skyrim.esm", in: data)
            // An empty plugins.txt names the active list explicitly, so the
            // fingerprint is the pinned masters and nothing the machine has.
            let pluginsText = install.appending(path: "plugins.txt", directoryHint: .notDirectory)
            try Data().write(to: pluginsText)
            let root = GameDataRoot(installURL: install, dataURL: data, source: .environment)

            let fingerprint = try OpenSkySaveStore.fingerprint(
                forRoot: root,
                location: .located(url: pluginsText, source: .installFolder)
            )

            #expect(fingerprint.map(\.name) == ["Skyrim.esm"])
        }
    }
}
