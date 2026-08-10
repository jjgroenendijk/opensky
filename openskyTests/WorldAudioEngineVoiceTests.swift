// Voice entry point (item 17.5): container framing, routing and error policy.
// The payload here is a synthetic xWMA stream, so the source starts, is routed
// and is reported exactly as a real line would be; it decodes to nothing,
// because no WMA fixture may enter the repository and the decode itself is
// covered by the real-data sweep instead.

import AVFAudio
@testable import opensky
import simd
import Testing

@MainActor
struct WorldAudioEngineVoiceTests {
    private func makeRunningEngine() throws -> WorldAudioEngine {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)
        )
        let engine = WorldAudioEngine(manualRenderingFormat: format)
        engine.isEnabled = true
        try #require(engine.isRunning, "offline engine failed: \(engine.unavailableReason ?? "")")
        return engine
    }

    /// A mono 44.1 kHz voice line, which is the shape every vanilla `.fuz`
    /// carries.
    private func makeVoiceFile(lipByteCount: Int = 1728) -> Data {
        FUZFixture.file(
            lipByteCount: lipByteCount,
            audio: XWMFixture.file(packetCount: 4, blockAlign: 1487, channelCount: 1)
        )
    }

    @Test("a voice line starts positionally on the voice submix and hands back its lip data")
    func playVoiceRoutesToVoiceCategory() throws {
        let engine = try makeRunningEngine()
        let playback = try engine.playVoice(
            fuzData: makeVoiceFile(),
            name: "sound\\voice\\skyrim.esm\\femaleeventoned\\wigreeting__000c7917_1.fuz",
            worldPosition: SIMD3(700, 0, 0)
        )
        #expect(playback.lipData?.count == 1728)
        let duration = try #require(playback.duration)
        #expect(duration > 0)
        let source = try #require(engine.sources.first)
        #expect(source.id == playback.sourceID)
        #expect(source.category == .voice)
        #expect(source.isPositional)
        #expect(source.worldPosition == SIMD3<Float>(700, 0, 0))
    }

    @Test("a line without lip data still plays")
    func playVoiceWithoutLipData() throws {
        let engine = try makeRunningEngine()
        let playback = try engine.playVoice(
            fuzData: makeVoiceFile(lipByteCount: 0), name: "line", worldPosition: .zero
        )
        #expect(playback.lipData == nil)
        #expect(engine.sources.count == 1)
    }

    @Test("a malformed container throws instead of starting a silent source")
    func malformedContainerThrows() throws {
        let engine = try makeRunningEngine()
        #expect(throws: FUZError.self) {
            try engine.playVoice(fuzData: Data([0, 1, 2, 3]), name: "line", worldPosition: .zero)
        }
        #expect(engine.sources.isEmpty)
    }

    @Test("a container whose payload is not xWMA throws from the audio side")
    func malformedPayloadThrows() throws {
        let engine = try makeRunningEngine()
        let file = FUZFixture.file(audio: Data(repeating: 7, count: 64))
        #expect(throws: XWMError.self) {
            try engine.playVoice(fuzData: file, name: "line", worldPosition: .zero)
        }
        #expect(engine.sources.isEmpty)
    }
}
