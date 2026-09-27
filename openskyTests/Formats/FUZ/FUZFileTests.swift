// `.fuz` (voice container) framing tests. Every fixture is built in code from
// the documented layout (docs/formats/fuz.md); no extracted game audio is
// involved. Malformed input must throw `FUZError`, never trap.

import Foundation
@testable import opensky
import Testing

@Suite("FUZ framing")
struct FUZFileTests {
    @Test("well-formed file exposes the version, the lip blob and the audio payload")
    func happyPath() throws {
        let audio = XWMFixture.file(packetCount: 2)
        let file = try FUZFile(data: FUZFixture.file(lipByteCount: 16, audio: audio))
        #expect(file.version == 1)
        #expect(file.lipByteCount == 16)
        #expect(file.lipData == FUZFixture.lip(byteCount: 16))
        #expect(file.audioData == audio)
        #expect(file.audioByteCount == audio.count)
    }

    @Test("the audio payload frames as xWMA through the container's own accessor")
    func audioFrames() throws {
        let file = try FUZFile(data: FUZFixture.file())
        let audio = try file.audio()
        #expect(audio.codec.formatTag == XWMFixture.formatTagWMAv2)
        #expect(audio.packetCount == 2)
    }

    @Test("a zero-length lip chunk is legal and reports no lip data")
    func zeroLengthLip() throws {
        let file = try FUZFile(data: FUZFixture.file(lipByteCount: 0))
        #expect(file.lipData == nil)
        #expect(file.lipByteCount == 0)
        #expect(!file.audioData.isEmpty)
    }

    @Test("wrong magic is malformed")
    func wrongMagic() {
        #expect(throws: FUZError.malformed("magic is FUZZ, expected FUZE")) {
            try FUZFile(data: FUZFixture.file(magic: "FUZZ"))
        }
    }

    @Test("a truncated header is malformed rather than a crash", arguments: 0 ... 11)
    func truncatedHeader(byteCount: Int) {
        let bytes = FUZFixture.file().prefix(byteCount)
        #expect(throws: FUZError.self) {
            try FUZFile(data: Data(bytes))
        }
    }

    @Test("a lip size past the end of the file is malformed")
    func lipSizeOverrunsFile() {
        #expect(throws: FUZError.self) {
            try FUZFile(data: FUZFixture.file(lipByteCount: 4, declaredLipSize: 1 << 20))
        }
    }

    @Test("a lip size claiming the whole payload leaves no audio and is malformed")
    func lipSizeEatsPayload() throws {
        let file = FUZFixture.file(lipByteCount: 8)
        let lipSize = UInt32(file.count - 12)
        #expect(throws: FUZError.malformed("no audio payload after \(lipSize) lip bytes")) {
            try FUZFile(data: FUZFixture.file(lipByteCount: 8, declaredLipSize: lipSize))
        }
    }

    @Test("an unknown container version is declined, not guessed at")
    func unknownVersion() {
        #expect(throws: FUZError.unsupported("container version 2")) {
            try FUZFile(data: FUZFixture.file(version: 2))
        }
    }

    @Test("an empty buffer is malformed")
    func emptyBuffer() {
        #expect(throws: FUZError.self) {
            try FUZFile(data: Data())
        }
    }
}
