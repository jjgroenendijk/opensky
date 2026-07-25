// `.xwm` (xWMA) container framing tests. Every fixture is built in code from
// the documented layout (docs/formats/xwm.md); no extracted game audio is
// involved. Malformed input must throw `XWMError`, never trap.

import Foundation
@testable import opensky
import Testing

@Suite("XWM framing")
struct XWMFileTests {
    @Test("well-formed file exposes codec parameters, packet table and payload")
    func happyPath() throws {
        let file = try XWMFile(data: XWMFixture.file(packetCount: 3))
        #expect(file.codec.formatTag == XWMFixture.formatTagWMAv2)
        #expect(file.codec.channelCount == 2)
        #expect(file.codec.sampleRate == 44100)
        #expect(file.codec.averageBytesPerSecond == 6000)
        #expect(file.codec.bitRate == 48000)
        #expect(file.codec.blockAlign == 2230)
        #expect(file.codec.bitsPerSample == 16)
        #expect(file.codec.extraData.isEmpty)
        #expect(file.codec.bytesPerDecodedFrame == 4)
        #expect(file.packetCumulativeDecodedBytes == [40960, 81920, 122_880])
        #expect(file.payloadByteCount == 3 * 2230)
        #expect(file.payload.count == 3 * 2230)
        #expect(file.packetCount == 3)
        #expect(file.isPacketTableConsistent)
    }

    @Test("declared duration comes from the last dpds entry")
    func declaredDuration() throws {
        let file = try XWMFile(data: XWMFixture.file(packetCount: 4))
        #expect(file.declaredDecodedByteCount == 163_840)
        // 163840 decoded bytes / (2 channels * 2 bytes) = 40960 sample frames.
        #expect(file.declaredSampleCount == 40960)
        let duration = try #require(file.declaredDuration)
        #expect(abs(duration - 40960.0 / 44100.0) < 0.0001)
    }

    @Test("packets are sliced at nBlockAlign and the last one may be short")
    func packetSlicing() throws {
        var chunks = XWMFixture.chunk("fmt ", XWMFixture.formatBody(blockAlign: 4))
        chunks.append(XWMFixture.chunk("data", Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])))
        let file = try XWMFile(data: XWMFixture.container(chunks: chunks))
        #expect(file.packetCount == 3)
        #expect(file.packet(at: 0) == Data([0, 1, 2, 3]))
        #expect(file.packet(at: 2) == Data([8, 9]))
        #expect(file.packet(at: 3) == nil)
        #expect(file.packet(at: -1) == nil)
    }

    @Test("a file without a dpds chunk frames, with no declared duration")
    func missingPacketTableIsTolerated() throws {
        var chunks = XWMFixture.chunk("fmt ", XWMFixture.formatBody(blockAlign: 4))
        chunks.append(XWMFixture.chunk("data", Data(repeating: 1, count: 8)))
        let file = try XWMFile(data: XWMFixture.container(chunks: chunks))
        #expect(file.packetCumulativeDecodedBytes.isEmpty)
        #expect(file.declaredDecodedByteCount == nil)
        #expect(file.declaredSampleCount == nil)
        #expect(file.declaredDuration == nil)
        #expect(file.isPacketTableConsistent)
    }

    @Test("a dpds table that does not match the packet count is reported, not rejected")
    func inconsistentPacketTable() throws {
        var chunks = XWMFixture.chunk("fmt ", XWMFixture.formatBody(blockAlign: 4))
        chunks.append(XWMFixture.chunk("dpds", XWMFixture.packetTableBody([16])))
        chunks.append(XWMFixture.chunk("data", Data(repeating: 1, count: 8)))
        let file = try XWMFile(data: XWMFixture.container(chunks: chunks))
        #expect(file.packetCount == 2)
        #expect(file.isPacketTableConsistent == false)
    }

    @Test("cbSize extradata is carried through to the decoder")
    func extraDataIsCarried() throws {
        let extra = Data([0, 0, 0, 0, 31, 0])
        var chunks = XWMFixture.chunk("fmt ", XWMFixture.formatBody(
            blockAlign: 4,
            extraData: extra
        ))
        chunks.append(XWMFixture.chunk("data", Data(repeating: 1, count: 8)))
        let file = try XWMFile(data: XWMFixture.container(chunks: chunks))
        #expect(file.codec.extraData == extra)
    }

    @Test("unknown chunks are skipped")
    func unknownChunksAreSkipped() throws {
        var chunks = XWMFixture.chunk("JUNK", Data(repeating: 7, count: 5))
        chunks.append(XWMFixture.chunk("fmt ", XWMFixture.formatBody(blockAlign: 4)))
        chunks.append(XWMFixture.chunk("data", Data(repeating: 1, count: 8)))
        let file = try XWMFile(data: XWMFixture.container(chunks: chunks))
        #expect(file.packetCount == 2)
    }
}

@Suite("XWM malformed input")
struct XWMFileMalformedTests {
    @Test("a buffer shorter than the RIFF header throws")
    func truncatedHeader() {
        for count in 0 ... 11 {
            #expect(throws: XWMError.self) {
                try XWMFile(data: Data(repeating: 0x52, count: count))
            }
        }
    }

    @Test("wrong magic or form type throws")
    func wrongSignature() {
        let chunks = XWMFixture.chunk("fmt ", XWMFixture.formatBody(blockAlign: 4))
            + XWMFixture.chunk("data", Data(repeating: 1, count: 8))
        #expect(throws: XWMError.self) {
            try XWMFile(data: XWMFixture.container(magic: "RIFX", chunks: chunks))
        }
        #expect(throws: XWMError.self) {
            try XWMFile(data: XWMFixture.container(formType: "WAVE", chunks: chunks))
        }
    }

    @Test("a truncated payload throws")
    func truncatedPayload() throws {
        let full = XWMFixture.file(packetCount: 3)
        let truncated = full.prefix(full.count - 1000)
        #expect(throws: XWMError.self) {
            try XWMFile(data: Data(truncated))
        }
    }

    @Test("a chunk length that overruns the file throws")
    func chunkLengthOverrunsFile() {
        var chunks = XWMFixture.chunk("fmt ", XWMFixture.formatBody(blockAlign: 4))
        // Claim 4096 payload bytes while supplying 8.
        var oversized = Data("data".utf8)
        oversized.appendUInt32(4096)
        oversized.append(Data(repeating: 1, count: 8))
        chunks.append(oversized)
        #expect(throws: XWMError.self) {
            try XWMFile(data: XWMFixture.container(chunks: chunks))
        }
    }

    @Test("a RIFF size larger than the buffer throws")
    func riffSizeOverrunsFile() {
        var chunks = XWMFixture.chunk("fmt ", XWMFixture.formatBody(blockAlign: 4))
        chunks.append(XWMFixture.chunk("data", Data(repeating: 1, count: 8)))
        #expect(throws: XWMError.self) {
            try XWMFile(data: XWMFixture.container(chunks: chunks, riffSize: 1 << 20))
        }
    }

    @Test("a missing required chunk throws")
    func missingRequiredChunk() {
        #expect(throws: XWMError.malformed("missing required \"data\" chunk")) {
            try XWMFile(data: XWMFixture.container(
                chunks: XWMFixture.chunk("fmt ", XWMFixture.formatBody(blockAlign: 4))
            ))
        }
        #expect(throws: XWMError.malformed("missing required \"fmt \" chunk")) {
            try XWMFile(data: XWMFixture.container(
                chunks: XWMFixture.chunk("data", Data(repeating: 1, count: 8))
            ))
        }
    }

    @Test("an unexpected format tag throws unsupported")
    func unexpectedFormatTag() {
        for tag in [UInt16(0x0001), 0x0162, 0x0163, 0xFFFF] {
            #expect(throws: XWMError.self) {
                try XWMFile(data: XWMFixture.file(formatTag: tag))
            }
        }
    }

    @Test("a zero-length payload throws")
    func zeroLengthPayload() {
        var chunks = XWMFixture.chunk("fmt ", XWMFixture.formatBody(blockAlign: 4))
        chunks.append(XWMFixture.chunk("data", Data()))
        #expect(throws: XWMError.malformed("\"data\" chunk is empty")) {
            try XWMFile(data: XWMFixture.container(chunks: chunks))
        }
    }

    @Test("a short fmt chunk throws")
    func shortFormatChunk() {
        var chunks = XWMFixture.chunk("fmt ", Data(repeating: 0, count: 16))
        chunks.append(XWMFixture.chunk("data", Data(repeating: 1, count: 8)))
        #expect(throws: XWMError.self) {
            try XWMFile(data: XWMFixture.container(chunks: chunks))
        }
    }

    @Test("out-of-range WAVEFORMATEX fields throw malformed")
    func invalidFormatFields() {
        for body in [
            XWMFixture.formatBody(channelCount: 0),
            XWMFixture.formatBody(channelCount: 64),
            XWMFixture.formatBody(sampleRate: 0),
            XWMFixture.formatBody(blockAlign: 0),
            XWMFixture.formatBody(bitsPerSample: 12)
        ] {
            var chunks = XWMFixture.chunk("fmt ", body)
            chunks.append(XWMFixture.chunk("data", Data(repeating: 1, count: 8)))
            #expect(throws: XWMError.self) {
                try XWMFile(data: XWMFixture.container(chunks: chunks))
            }
        }
    }

    @Test("a dpds chunk that is not a whole number of entries throws")
    func misalignedPacketTable() {
        var chunks = XWMFixture.chunk("fmt ", XWMFixture.formatBody(blockAlign: 4))
        chunks.append(XWMFixture.chunk("dpds", Data(repeating: 0, count: 6)))
        chunks.append(XWMFixture.chunk("data", Data(repeating: 1, count: 8)))
        #expect(throws: XWMError.malformed("\"dpds\" chunk size 6 is not a multiple of 4")) {
            try XWMFile(data: XWMFixture.container(chunks: chunks))
        }
    }

    @Test("duplicate required chunks throw")
    func duplicateChunks() {
        let format = XWMFixture.chunk("fmt ", XWMFixture.formatBody(blockAlign: 4))
        let payload = XWMFixture.chunk("data", Data(repeating: 1, count: 8))
        #expect(throws: XWMError.malformed("duplicate \"fmt \" chunk")) {
            try XWMFile(data: XWMFixture.container(chunks: format + format + payload))
        }
        #expect(throws: XWMError.malformed("duplicate \"data\" chunk")) {
            try XWMFile(data: XWMFixture.container(chunks: format + payload + payload))
        }
        let table = XWMFixture.chunk("dpds", XWMFixture.packetTableBody([16, 32]))
        #expect(throws: XWMError.malformed("duplicate \"dpds\" chunk")) {
            try XWMFile(data: XWMFixture.container(chunks: format + table + table + payload))
        }
    }
}
