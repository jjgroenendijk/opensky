import AVFAudio
import OpenSkyAudio
import OpenSkySessionInterface
import OpenSkySessionTesting
import Testing

/// A session whose world audio plays one looping positional sound, for the sound commands.
@MainActor
struct PlayingLoopSession {
    let session: FakeGameSessionPort
    let engine: WorldAudioEngine
    let id: Int

    init() throws {
        session = FakeGameSessionPort()
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        engine = WorldAudioEngine(manualRenderingFormat: format)
        engine.isEnabled = true
        let tone = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 441))
        tone.frameLength = 441
        id = try engine.playPositional(
            buffer: tone,
            request: AudioPlayRequest(
                name: "loop.wav", category: .effects, worldPosition: [64, 0, 0], loops: true
            )
        )
        session.worldAudio = engine
    }
}
