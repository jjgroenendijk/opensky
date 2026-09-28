// Load-order fingerprint tests for the OpenSky native save container
// (issue #161).
//
// Verification is separate from decoding, so these tests build a decoded file
// directly and check it against a hypothetical installed load order. Every
// mismatch case asserts the exact reason string, because that text is what the
// app shows the user when a save refuses to load.

import Foundation
@testable import opensky
import Testing

struct OpenSkySaveFingerprintTests {
    // MARK: - Fixtures

    private let saved = OpenSkySaveFixture.fingerprint

    private func file(_ fingerprint: [SavePluginFingerprint]) -> OpenSkySaveFile {
        OpenSkySaveFile(
            formatVersion: OpenSkySaveFormat.currentVersion,
            metadata: OpenSkySaveFixture.metadata,
            fingerprint: fingerprint,
            snapshot: .empty,
            allocator: GeneratedReferenceAllocator()
        )
    }

    private func changing(
        _ index: Int,
        name: String? = nil,
        hedrVersion: Float? = nil,
        recordCount: Int32? = nil,
        nextObjectID: UInt32? = nil
    ) -> [SavePluginFingerprint] {
        var plugins = saved
        let original = plugins[index]
        plugins[index] = SavePluginFingerprint(
            name: name ?? original.name,
            hedrVersion: hedrVersion ?? original.hedrVersion,
            recordCount: recordCount ?? original.recordCount,
            nextObjectID: nextObjectID ?? original.nextObjectID
        )
        return plugins
    }

    private func expectMismatch(_ current: [SavePluginFingerprint], reason: String) {
        #expect(throws: OpenSkySaveError.fingerprintMismatch(reason: reason)) {
            try file(saved).verifyFingerprint(against: current)
        }
    }

    // MARK: - Matches

    @Test func anIdenticalLoadOrderVerifies() throws {
        try file(saved).verifyFingerprint(against: saved)
    }

    @Test func anEmptyLoadOrderVerifiesAgainstAnEmptySave() throws {
        try file([]).verifyFingerprint(against: [])
    }

    @Test func fileNameCaseIsIgnored() throws {
        let current = changing(0, name: "SKYRIM.ESM")
        try file(saved).verifyFingerprint(against: current)
        try file(current).verifyFingerprint(against: saved)
    }

    // MARK: - Mismatches

    @Test func aChangedRecordCountIsAMismatch() {
        expectMismatch(
            changing(0, recordCount: 1_234_568),
            reason: "plugin 'Skyrim.esm' changed since the save was written"
        )
    }

    @Test func aChangedHeaderVersionIsAMismatch() {
        expectMismatch(
            changing(1, hedrVersion: 1.7),
            reason: "plugin 'Dawnguard.esm' changed since the save was written"
        )
    }

    @Test func aChangedNextObjectIDIsAMismatch() {
        expectMismatch(
            changing(1, nextObjectID: 0x0000_0801),
            reason: "plugin 'Dawnguard.esm' changed since the save was written"
        )
    }

    @Test func aMissingPluginIsAMismatch() {
        expectMismatch(
            Array(saved.prefix(1)),
            reason: "plugin 'Dawnguard.esm' was loaded when the save was written "
                + "but is not loaded now"
        )
    }

    @Test func anExtraPluginIsAMismatch() {
        let extra = SavePluginFingerprint(
            name: "Dragonborn.esm",
            hedrVersion: 1.71,
            recordCount: 10,
            nextObjectID: 0x800
        )
        expectMismatch(
            saved + [extra],
            reason: "plugin 'Dragonborn.esm' is loaded now but was not loaded "
                + "when the save was written"
        )
    }

    @Test func aReorderedLoadOrderIsAMismatch() {
        expectMismatch(
            Array(saved.reversed()),
            reason: "load order changed at position 0: the save expects "
                + "'Skyrim.esm' where 'Dawnguard.esm' is loaded now"
        )
    }

    @Test func theFirstDifferenceIsTheOneReported() {
        // Position 0 is renamed and position 1 is edited; the earlier
        // difference wins so the message points at the root cause.
        var current = changing(0, name: "Update.esm")
        current[1] = SavePluginFingerprint(
            name: saved[1].name,
            hedrVersion: saved[1].hedrVersion,
            recordCount: 0,
            nextObjectID: saved[1].nextObjectID
        )
        expectMismatch(
            current,
            reason: "load order changed at position 0: the save expects "
                + "'Skyrim.esm' where 'Update.esm' is loaded now"
        )
    }

    // MARK: - Construction from a plugin header

    @Test func aFingerprintIsBuiltFromTheHeaderStats() {
        let stats = PluginHeader.Stats(
            version: 1.71,
            recordCount: 1_234_567,
            nextObjectID: 0x0010_0000
        )
        let fingerprint = SavePluginFingerprint(pluginName: "Skyrim.esm", stats: stats)
        #expect(fingerprint == saved[0])
        #expect(fingerprint.name == "Skyrim.esm")
        #expect(fingerprint.hedrVersion == 1.71)
        #expect(fingerprint.recordCount == 1_234_567)
        #expect(fingerprint.nextObjectID == 0x0010_0000)
    }

    @Test func negativeRecordCountsSurviveTheBitPatternRoundTrip() throws {
        let stats = PluginHeader.Stats(version: 0.94, recordCount: -5, nextObjectID: 0x800)
        let fingerprint = SavePluginFingerprint(pluginName: "Dawnguard.esm", stats: stats)
        #expect(fingerprint == saved[1])

        let encoded = OpenSkySaveEncoder.encode(
            snapshot: .empty,
            fingerprint: [fingerprint],
            metadata: OpenSkySaveFixture.metadata
        )
        let decoded = try OpenSkySaveDecoder.decode(encoded)
        #expect(decoded.fingerprint == [fingerprint])
        #expect(decoded.fingerprint.first?.recordCount == -5)
    }

    @Test func stateComparisonHelpersDistinguishNameFromStats() {
        let renamed = SavePluginFingerprint(
            name: "SKYRIM.ESM",
            hedrVersion: saved[0].hedrVersion,
            recordCount: saved[0].recordCount,
            nextObjectID: saved[0].nextObjectID
        )
        #expect(saved[0].namesSamePlugin(as: renamed))
        #expect(saved[0].hasSameStats(as: renamed))
        #expect(saved[0].namesSamePlugin(as: saved[1]) == false)
        #expect(saved[0].hasSameStats(as: saved[1]) == false)
    }
}
