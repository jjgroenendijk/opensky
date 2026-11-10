// PCM `.wav` playback. A `.wav` effect is tiny (a footstep is about 26 KB), so it
// is read into one buffer and scheduled once; long `.xwm` tracks stream instead.

public import AVFAudio
import Foundation
public import OpenSkyFormatsAudio

extension WorldAudioEngine {
    /// Builds a PCM buffer from RIFF/WAVE bytes.
    ///
    /// `downmixToMono` averages the channels, which the positional path needs:
    /// `AVAudioEnvironmentNode` spatializes mono inputs and passes stereo
    /// through unspatialized (the same rule `AudioSourceStreamer.monoDownmix`
    /// follows for streamed sources).
    nonisolated static func makeBuffer(
        wav data: Data,
        downmixToMono: Bool
    ) throws -> AVAudioPCMBuffer {
        try makeBuffer(wav: WAVFile(data: data), downmixToMono: downmixToMono)
    }

    nonisolated public static func makeBuffer(
        wav file: WAVFile,
        downmixToMono: Bool
    ) throws -> AVAudioPCMBuffer {
        try makeBuffer(
            decoded: DecodedAudio(
                sampleRate: file.format.sampleRate, channelCount: file.format.channelCount,
                samples: file.samples
            ),
            downmixToMono: downmixToMono
        )
    }

    /// Builds a PCM buffer from interleaved samples, such as a cached ALAC file.
    nonisolated public static func makeBuffer(
        decoded audio: DecodedAudio,
        downmixToMono: Bool
    ) throws -> AVAudioPCMBuffer {
        let sourceChannels = audio.channelCount
        let frames = audio.frameCount
        let channels = downmixToMono ? 1 : sourceChannels
        guard
            channels > 0,
            frames > 0,
            let format = AVAudioFormat(
                standardFormatWithSampleRate: Double(audio.sampleRate),
                channels: AVAudioChannelCount(channels)
            ),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frames)
            ),
            let target = unsafe buffer.floatChannelData
        else {
            throw AudioEngineError.formatUnavailable
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        for frame in 0 ..< frames {
            let base = frame * sourceChannels
            if downmixToMono {
                var sum: Float = 0
                for channel in 0 ..< sourceChannels {
                    sum += audio.samples[base + channel]
                }
                unsafe target[0][frame] = sum / Float(sourceChannels)
            } else {
                for channel in 0 ..< sourceChannels {
                    unsafe target[channel][frame] = audio.samples[base + channel]
                }
            }
        }
        return buffer
    }
}
