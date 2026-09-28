// Offline audio-graph fixtures shared by the non-positional and fade suites.

import AVFAudio
@testable import OpenSkyAudio
import simd
import Testing

/// Shared offline fixtures for the non-positional and fade suites.
@MainActor
enum MusicAudioFixture {
    static let sampleRate = 44100.0

    static func makeRunningEngine() throws -> WorldAudioEngine {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
        )
        let engine = WorldAudioEngine(manualRenderingFormat: format)
        engine.isEnabled = true
        try #require(engine.isRunning, "offline engine failed: \(engine.unavailableReason ?? "")")
        return engine
    }

    /// Stereo tone, the shape music material has.
    static func makeStereoBuffer(seconds: Double = 0.25) throws -> AVAudioPCMBuffer {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
        )
        let frameCount = AVAudioFrameCount(seconds * sampleRate)
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        )
        let channels = try #require(buffer.floatChannelData)
        for frame in 0 ..< Int(frameCount) {
            let sample = sinf(2 * .pi * 440 * Float(frame) / Float(sampleRate)) * 0.5
            channels[0][frame] = sample
            channels[1][frame] = sample
        }
        buffer.frameLength = frameCount
        return buffer
    }

    /// Root-mean-square of exactly 0.2 s of offline render across both channels.
    ///
    /// `scheduleBuffer` hands the buffer to the player node asynchronously, so
    /// rendering can begin with silence or start partway through a chunk. The
    /// measurement begins at the first frame carrying signal and covers a fixed
    /// number of frames: how long the node took to start is machine load, not
    /// signal level (issues #240 and #255).
    static func renderRMS(_ engine: WorldAudioEngine) throws -> Float {
        let format = engine.engine.manualRenderingFormat
        let chunk = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096))
        var sum: Float = 0
        var measuredFrames = 0
        var started = false
        var attempts = 0
        let targetFrames = 8820
        while measuredFrames < targetFrames, attempts < 64 {
            attempts += 1
            let status = try engine.engine.renderOffline(4096, to: chunk)
            guard status == .success else { continue }
            let channels = try #require(chunk.floatChannelData)
            var firstFrame = 0
            if !started {
                firstFrame = Int(chunk.frameLength)
                findSignal: for frame in 0 ..< Int(chunk.frameLength) {
                    for channel in 0 ..< Int(format.channelCount)
                        where channels[channel][frame] != 0
                    {
                        firstFrame = frame
                        started = true
                        break findSignal
                    }
                }
                guard started else { continue }
            }
            let frameCount = min(
                Int(chunk.frameLength) - firstFrame,
                targetFrames - measuredFrames
            )
            for channel in 0 ..< Int(format.channelCount) {
                for frame in firstFrame ..< firstFrame + frameCount {
                    let sample = channels[channel][frame]
                    sum += sample * sample
                }
            }
            measuredFrames += frameCount
        }
        try #require(measuredFrames == targetFrames, "offline player produced no signal")
        return sqrtf(sum / Float(measuredFrames * Int(format.channelCount)))
    }

    @discardableResult
    static func playMusic(
        _ engine: WorldAudioEngine, name: String = "music\\test.xwm", gain: Float = 1
    ) throws -> Int {
        try engine.playNonPositional(
            buffer: makeStereoBuffer(),
            request: .nonPositional(name: name, category: .music, gain: gain, loops: true)
        )
    }

    /// Mono one-shot through the positional path — the environment node only
    /// spatializes mono inputs.
    static func playEffect(
        _ engine: WorldAudioEngine, name: String, at worldPosition: SIMD3<Float> = .zero
    ) throws {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        )
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128))
        buffer.frameLength = 128
        try engine.playPositional(buffer: buffer, request: AudioPlayRequest(
            name: name, category: .effects, worldPosition: worldPosition
        ))
    }
}
