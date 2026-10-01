// The offline engine, test tone, and level reading that the world-audio suites
// share. Nothing plays: the engine renders in manual mode.

import AVFAudio
@testable import OpenSkyAudio
import Testing

@MainActor
enum OfflineAudioFixture {
    static let sampleRate = 44100.0

    /// A stereo engine in manual rendering mode, already enabled and running.
    static func makeRunningEngine() throws -> WorldAudioEngine {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
        )
        let engine = WorldAudioEngine(manualRenderingFormat: format)
        engine.isEnabled = true
        try #require(engine.isRunning, "offline engine failed: \(engine.unavailableReason ?? "")")
        return engine
    }

    /// A mono 440 Hz tone at half scale.
    static func makeToneBuffer(seconds: Double = 0.25) throws -> AVAudioPCMBuffer {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        )
        let frameCount = AVAudioFrameCount(seconds * sampleRate)
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        )
        let channel = try #require(buffer.floatChannelData?[0])
        for frame in 0 ..< Int(frameCount) {
            channel[frame] = sinf(2 * .pi * 440 * Float(frame) / Float(sampleRate)) * 0.5
        }
        buffer.frameLength = frameCount
        return buffer
    }

    /// Renders about 0.2 s and returns the RMS level of each channel.
    static func channelRMS(_ engine: WorldAudioEngine) throws -> [Float] {
        let format = engine.engine.manualRenderingFormat
        let chunk = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096))
        var sums = [Float](repeating: 0, count: Int(format.channelCount))
        var frames = 0
        while frames < 8820 {
            let status = try engine.engine.renderOffline(4096, to: chunk)
            guard status == .success else { break }
            let channels = try #require(chunk.floatChannelData)
            for channel in 0 ..< Int(format.channelCount) {
                for frame in 0 ..< Int(chunk.frameLength) {
                    let sample = channels[channel][frame]
                    sums[channel] += sample * sample
                }
            }
            frames += Int(chunk.frameLength)
        }
        return sums.map { sqrtf($0 / Float(max(frames, 1))) }
    }
}
