// PCM `.wav` playback. A `.wav` effect is tiny (a footstep is about 26 KB), so it
// is read into one buffer and scheduled once; long `.xwm` tracks stream instead.

import AVFAudio
import Foundation
import OpenSkyFormatsAudio

extension WorldAudioEngine {
    /// Builds a PCM buffer from RIFF/WAVE bytes.
    ///
    /// `downmixToMono` averages the channels, which the positional path needs:
    /// `AVAudioEnvironmentNode` spatializes mono inputs and passes stereo
    /// through unspatialized (the same rule `AudioSourceStreamer.monoDownmix`
    /// follows for streamed sources).
    nonisolated public static func makeBuffer(
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
            let target = buffer.floatChannelData
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
                target[0][frame] = sum / Float(sourceChannels)
            } else {
                for channel in 0 ..< sourceChannels {
                    target[channel][frame] = audio.samples[base + channel]
                }
            }
        }
        return buffer
    }

    /// True when `data` is a RIFF/WAVE form rather than a RIFF/XWMA one. The
    /// two share the RIFF header and differ in the form type at byte 8, so a
    /// twelve-byte peek decides which player path a file takes without parsing
    /// either container.
    nonisolated public static func isWAV(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        let start = data.startIndex
        let magic = data[start ..< start + 4]
        let form = data[(start + 8) ..< (start + 12)]
        return magic.elementsEqual(Array("RIFF".utf8))
            && form.elementsEqual(Array("WAVE".utf8))
    }
}
