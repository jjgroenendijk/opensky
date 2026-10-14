import Foundation
@testable import OpenSkyAudio
@testable import OpenSkyFormatsAudio
import OpenSkyFormatsTesting
import Testing

struct VoiceLineFilesTests {
    private struct Missing: Error {}

    private static func contents(_ path: String, files: [String: Data]) throws -> Data {
        try VoiceLineFiles.contents(
            forPath: path,
            exists: { files[$0] != nil },
            read: { path in
                guard let data = files[path] else { throw Missing() }
                return data
            }
        )
    }

    @Test("a .fuz is read as it is")
    func fuz() throws {
        let fuz = FUZFixture.file()
        #expect(try Self.contents("line.fuz", files: ["line.fuz": fuz, "line.xwm": Data([1])])
            == fuz)
    }

    @Test("loose .xwm and .lip join into one container")
    func looseFiles() throws {
        let audio = XWMFixture.file(packetCount: 2)
        let lip = FUZFixture.lip(byteCount: 8)
        let joined = try FUZFile(
            data: Self.contents("line.fuz", files: ["line.xwm": audio, "line.lip": lip])
        )
        #expect(joined.lipData == lip)
        #expect(joined.audioData == audio)

        let silent = try FUZFile(data: Self.contents("line.fuz", files: ["line.xwm": audio]))
        #expect(silent.lipData == nil)
    }

    @Test("with nothing on disk the .fuz read's error comes back")
    func missing() {
        #expect(throws: Missing.self) {
            try Self.contents("line.fuz", files: ["line.lip": Data([1])])
        }
    }
}
