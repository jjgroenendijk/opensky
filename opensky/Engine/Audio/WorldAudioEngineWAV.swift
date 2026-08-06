// PCM `.wav` playback for WorldAudioEngine (issue #352). Satellite of
// WorldAudioEngineSources.swift, which owns the streamed `.xwm` path.
//
// The two formats are played differently on purpose. An `.xwm` music track is
// minutes long and tens of megabytes of PCM, so it streams: decode a chunk,
// schedule it, repeat. A `.wav` sound effect is a fraction of a second — the
// vanilla footstep files are around 26 KB — so it is read whole into one
// buffer and scheduled once. Streaming it would add a decode-queue hop and a
// three-buffer lookahead to something that fits in a single scheduling call.

import AVFAudio
import Foundation

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
        let file = try WAVFile(data: data)
        let channels = downmixToMono ? 1 : file.format.channelCount
        guard
            channels > 0,
            file.frameCount > 0,
            let format = AVAudioFormat(
                standardFormatWithSampleRate: Double(file.format.sampleRate),
                channels: AVAudioChannelCount(channels)
            ),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(file.frameCount)
            ),
            let target = buffer.floatChannelData
        else {
            throw AudioEngineError.formatUnavailable
        }
        buffer.frameLength = AVAudioFrameCount(file.frameCount)
        let sourceChannels = file.format.channelCount
        for frame in 0 ..< file.frameCount {
            let base = frame * sourceChannels
            if downmixToMono {
                var sum: Float = 0
                for channel in 0 ..< sourceChannels {
                    sum += file.samples[base + channel]
                }
                target[0][frame] = sum / Float(sourceChannels)
            } else {
                for channel in 0 ..< sourceChannels {
                    target[channel][frame] = file.samples[base + channel]
                }
            }
        }
        return buffer
    }

    /// True when `data` is a RIFF/WAVE form rather than a RIFF/XWMA one. The
    /// two share the RIFF header and differ in the form type at byte 8, so a
    /// twelve-byte peek decides which player path a file takes without parsing
    /// either container.
    nonisolated static func isWAV(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        let start = data.startIndex
        let magic = data[start ..< start + 4]
        let form = data[(start + 8) ..< (start + 12)]
        return magic.elementsEqual(Array("RIFF".utf8))
            && form.elementsEqual(Array("WAVE".utf8))
    }
}
