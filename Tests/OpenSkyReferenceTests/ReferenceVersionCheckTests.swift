// The version check between the reference copy and the OpenSky install.

import Foundation
@testable import OpenSkyReference
import Testing

struct ReferenceVersionCheckTests {
    @Test func buildIDComesFromTheManifest() {
        let manifest = """
        "AppState"
        {
        \t"appid"\t\t"489830"
        \t"buildid"\t\t"13189953"
        \t"TargetBuildID"\t\t"13189953"
        }
        """
        #expect(ReferenceInstallFingerprint.buildID(inManifest: manifest) == "13189953")
        #expect(ReferenceInstallFingerprint.buildID(inManifest: "{}") == nil)
    }

    @Test func matchingInstallsHaveNoMismatch() {
        let print = ReferenceInstallFingerprint(buildID: "1", masters: ["skyrim.esm": "aa"])
        #expect(ReferenceVersionCheck.compare(opensky: print, reference: print).isEmpty)
    }

    @Test func everyDifferenceIsNamed() {
        let opensky = ReferenceInstallFingerprint(
            buildID: "1", masters: ["skyrim.esm": "aa", "update.esm": "bb", "dawnguard.esm": "cc"]
        )
        let reference = ReferenceInstallFingerprint(
            buildID: "2", masters: ["skyrim.esm": "aa", "update.esm": "xx", "hearthfires.esm": "dd"]
        )
        #expect(ReferenceVersionCheck.compare(opensky: opensky, reference: reference) == [
            .buildID(opensky: "1", reference: "2"),
            .onlyInOpenSky("dawnguard.esm"),
            .onlyInReference("hearthfires.esm"),
            .differs("update.esm")
        ])
    }

    @Test func anUnknownBuildIDIsAMismatch() {
        let print = ReferenceInstallFingerprint(buildID: nil, masters: [:])
        #expect(ReferenceVersionCheck.compare(opensky: print, reference: print) == [
            .buildID(opensky: nil, reference: nil)
        ])
    }

    @Test func fingerprintHashesEachMaster() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "reference-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = folder.appending(path: "Data", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try Data("abc".utf8).write(to: data.appending(path: "Test.esm"))
        try Data("x".utf8).write(to: data.appending(path: "Test.bsa"))
        let manifest = folder.appending(path: "appmanifest.acf")
        try Data("\"buildid\"\t\t\"7\"".utf8).write(to: manifest)

        let print = try await ReferenceInstallFingerprint.read(
            gameDirectory: folder, manifest: manifest
        )
        #expect(print.buildID == "7")
        #expect(print.masters == [
            "test.esm": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        ])
    }
}
