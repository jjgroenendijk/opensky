// Malformed-input tests for the OpenSky native save container (issue #161):
// header, fingerprint, chunk framing and string fields.
//
// AGENTS.md requires that malformed input never crashes, so every case here
// asserts the exact `OpenSkySaveError` a specific byte-level defect produces
// rather than merely that something was thrown. Entry-level defects — keys,
// cells and component values — live in OpenSkySaveEntryCorruptionTests.

import Foundation
@testable import opensky
import Testing

struct OpenSkySaveCorruptionTests {
    // MARK: - Layout of the fixture file

    private let save = OpenSkySaveFixture.encodedRichSave()

    private var fingerprintOffset: Int {
        OpenSkySaveFixture.fingerprintOffset(in: save)
    }

    /// Offset of the second plugin's name inside the fingerprint section.
    private var secondPluginOffset: Int {
        let first = OpenSkySaveFixture.pluginEntrySize(OpenSkySaveFixture.fingerprint[0])
        return fingerprintOffset + 4 + first
    }

    private func chunkOffset(_ tag: String) throws -> Int {
        try #require(OpenSkySaveFixture.offset(ofChunk: tag, in: save))
    }

    private func expectTruncated(at length: Int, context: String) {
        #expect(throws: OpenSkySaveError.truncated(context: context)) {
            try OpenSkySaveDecoder.decode(OpenSkySaveFixture.truncating(save, to: length))
        }
    }

    // MARK: - Header

    @Test func emptyDataIsATruncatedMagic() {
        #expect(throws: OpenSkySaveError.truncated(context: "magic")) {
            try OpenSkySaveDecoder.decode(Data())
        }
    }

    @Test func dataShorterThanTheMagicIsTruncated() {
        expectTruncated(at: 2, context: "magic")
        expectTruncated(at: 3, context: "magic")
    }

    @Test func aFileThatIsNotOSAVIsRejected() {
        let patched = OpenSkySaveFixture.patching(save, at: 0, with: Array("XSAV".utf8))
        #expect(throws: OpenSkySaveError.badMagic) {
            try OpenSkySaveDecoder.decode(patched)
        }
        // A plausible near-miss is still a miss.
        let lowercased = OpenSkySaveFixture.patching(save, at: 0, with: Array("osav".utf8))
        #expect(throws: OpenSkySaveError.badMagic) {
            try OpenSkySaveDecoder.decode(lowercased)
        }
    }

    @Test func anUnimplementedVersionIsRejectedWithTheVersionItFound() {
        for version: UInt32 in [0, 2, .max] {
            let data = OpenSkySaveFixture.file(chunks: [], version: version)
            #expect(throws: OpenSkySaveError.unsupportedVersion(found: version)) {
                try OpenSkySaveDecoder.decode(data)
            }
        }
    }

    // MARK: - Truncation at structural offsets

    @Test func truncationInsideTheHeaderNamesTheStructureItLandedIn() {
        expectTruncated(at: 4, context: "format version")
        expectTruncated(at: 6, context: "format version")
        expectTruncated(at: 10, context: "metadata length")
        expectTruncated(at: 12, context: "metadata")
        expectTruncated(
            at: 12 + OpenSkySaveFixture.metadataBlockLength(in: save) / 2,
            context: "metadata"
        )
    }

    @Test func truncationInsideTheFingerprintNamesTheStructureItLandedIn() {
        expectTruncated(at: fingerprintOffset + 2, context: "fingerprint plugin count")
        // Far enough in that the plugin count still fits the bytes that remain,
        // so this is a truncated name rather than an impossible count.
        expectTruncated(at: secondPluginOffset + 7, context: "plugin name")
        let statsOffset = secondPluginOffset
            + OpenSkySaveFixture.pluginEntrySize(OpenSkySaveFixture.fingerprint[1]) - 12
        expectTruncated(at: statsOffset + 2, context: "plugin HEDR version")
        expectTruncated(at: statsOffset + 6, context: "plugin record count")
        expectTruncated(at: statsOffset + 10, context: "plugin next object ID")
    }

    @Test func truncationInsideAChunkHeaderNamesTheStructureItLandedIn() throws {
        let allocator = try chunkOffset(OpenSkySaveFormat.ChunkTag.allocator)
        expectTruncated(at: allocator + 2, context: "chunk tag")
        expectTruncated(at: allocator + 6, context: "chunk length")
        let deltas = try chunkOffset(OpenSkySaveFormat.ChunkTag.referenceDeltas)
        expectTruncated(at: deltas + 1, context: "chunk tag")
    }

    @Test func truncationInsideAChunkPayloadIsABoundsViolation() throws {
        // The declared payload length is checked against the bytes remaining
        // before any of it is read, so a cut payload reports the chunk rather
        // than a nameless truncation.
        let allocator = try chunkOffset(OpenSkySaveFormat.ChunkTag.allocator)
        let violation = OpenSkySaveError.chunkBoundsViolation(
            tag: OpenSkySaveFormat.ChunkTag.allocator
        )
        #expect(throws: violation) {
            try OpenSkySaveDecoder.decode(OpenSkySaveFixture.truncating(save, to: allocator + 12))
        }
    }

    @Test func everyTruncationLengthFailsCleanlyOrParses() throws {
        // Belt and braces over the named cases above: some prefixes are
        // legitimately complete files (the header plus a whole number of
        // chunks), and every other prefix must produce an OpenSkySaveError
        // rather than a crash or a foreign error type.
        for length in 0 ... save.count {
            let prefix = OpenSkySaveFixture.truncating(save, to: length)
            do {
                _ = try OpenSkySaveDecoder.decode(prefix)
            } catch is OpenSkySaveError {
                continue
            } catch {
                Issue.record("truncating to \(length) threw \(type(of: error)): \(error)")
            }
        }
    }

    // MARK: - Counts

    @Test func anImpossiblePluginCountIsRejectedBeforeAllocation() {
        var writer = BinaryWriter()
        writer.writeUInt32(.max)
        let patched = OpenSkySaveFixture.patching(
            save,
            at: fingerprintOffset,
            with: Array(writer.data)
        )
        let expected = OpenSkySaveError.invalidCount(
            chunk: "fingerprint",
            count: .max,
            remaining: save.count - fingerprintOffset - 4
        )
        #expect(throws: expected) {
            try OpenSkySaveDecoder.decode(patched)
        }
    }

    @Test func anImpossibleEntryCountIsRejectedBeforeAllocation() {
        let data = OpenSkySaveFixture.file(chunks: [OpenSkySaveFixture.deltasChunk(count: .max)])
        let expected = OpenSkySaveError.invalidCount(
            chunk: OpenSkySaveFormat.ChunkTag.referenceDeltas,
            count: .max,
            remaining: 0
        )
        #expect(throws: expected) {
            try OpenSkySaveDecoder.decode(data)
        }
    }

    @Test func anEntryCountLargerThanThePayloadCanHoldIsRejected() {
        let entry = OpenSkySaveFixture.entryBytes(componentCount: 0, components: Data())
        let data = OpenSkySaveFixture.file(chunks: [
            OpenSkySaveFixture.deltasChunk(count: 3, entries: entry)
        ])
        let expected = OpenSkySaveError.invalidCount(
            chunk: OpenSkySaveFormat.ChunkTag.referenceDeltas,
            count: 3,
            remaining: entry.count
        )
        #expect(throws: expected) {
            try OpenSkySaveDecoder.decode(data)
        }
    }

    // MARK: - Chunk framing

    @Test func aChunkLengthPastTheEndOfTheFileIsABoundsViolation() {
        let known = OpenSkySaveFixture.chunk(
            OpenSkySaveFormat.ChunkTag.allocator,
            Data(count: 8),
            declaredLength: 999
        )
        #expect(throws: OpenSkySaveError.chunkBoundsViolation(tag: "GALC")) {
            try OpenSkySaveDecoder.decode(OpenSkySaveFixture.file(chunks: [known]))
        }
        // An unknown tag is skipped by its declared length, so an impossible
        // length there is caught by the same check rather than ignored.
        let unknown = OpenSkySaveFixture.chunk("ZZZZ", Data(count: 4), declaredLength: .max)
        #expect(throws: OpenSkySaveError.chunkBoundsViolation(tag: "ZZZZ")) {
            try OpenSkySaveDecoder.decode(OpenSkySaveFixture.file(chunks: [unknown]))
        }
    }

    @Test func anAllocatorChunkThatIsNotEightBytesIsRejected() {
        for size in [0, 7, 9, 16] {
            let chunk = OpenSkySaveFixture.chunk(
                OpenSkySaveFormat.ChunkTag.allocator,
                Data(count: size)
            )
            let expected = OpenSkySaveError.invalidValue(
                context: "GALC payload is \(size) bytes, expected 8"
            )
            #expect(throws: expected) {
                try OpenSkySaveDecoder.decode(OpenSkySaveFixture.file(chunks: [chunk]))
            }
        }
    }

    // MARK: - Strings

    @Test func aStringLengthPastTheRemainingBytesIsATruncation() {
        let data = OpenSkySaveFixture.file(chunks: [], plugins: [OpenSkySaveFixture.fingerprint[0]])
        let patched = OpenSkySaveFixture.patching(
            data,
            at: OpenSkySaveFixture.fingerprintOffset(in: data) + 4,
            with: [0xFF, 0xFF]
        )
        #expect(throws: OpenSkySaveError.truncated(context: "plugin name")) {
            try OpenSkySaveDecoder.decode(patched)
        }
    }

    @Test func aStringThatIsNotValidUTF8IsRejected() {
        let data = OpenSkySaveFixture.file(chunks: [], plugins: [OpenSkySaveFixture.fingerprint[0]])
        let patched = OpenSkySaveFixture.patching(
            data,
            at: OpenSkySaveFixture.fingerprintOffset(in: data) + 6,
            with: [0xFF, 0xFE]
        )
        let expected = OpenSkySaveError.invalidValue(context: "plugin name is not valid UTF-8")
        #expect(throws: expected) {
            try OpenSkySaveDecoder.decode(patched)
        }
    }

    @Test func anAppVersionThatIsNotValidUTF8IsRejected() {
        // Offset 12 is the metadata block: eight timestamp bytes, then the
        // two-byte string length, then the text.
        let patched = OpenSkySaveFixture.patching(save, at: 22, with: [0xFF, 0xFF])
        let expected = OpenSkySaveError.invalidValue(
            context: "metadata app version is not valid UTF-8"
        )
        #expect(throws: expected) {
            try OpenSkySaveDecoder.decode(patched)
        }
    }
}
