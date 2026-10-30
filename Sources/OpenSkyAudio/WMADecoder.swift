// WMAv2 packet decoder: packets in, interleaved Float PCM out, through one
// `FFmpegCodecSession`. Codec parameters come from the xWMA header. See
// docs/decisions/ffmpeg-audio.md.

import CFFmpeg
import Foundation

nonisolated public final class WMADecoder {
    /// `WAVEFORMATEX.wFormatTag` for Windows Media Audio 2, the codec xWMA carries.
    public static let wmaV2FormatTag: UInt16 = 0x0161
    /// Above this the decoder rejects the header rather than trusting a wild channel count.
    public static let maximumChannelCount = 8

    public let parameters: AudioCodecParameters

    private let session: FFmpegCodecSession
    private var resampler: FFmpegResampler?

    /// Sample rate of the PCM this decoder produces, equal to the container's rate.
    public var outputSampleRate: Int {
        parameters.sampleRate
    }

    /// Channel count of the PCM this decoder produces, equal to the container's count.
    public var outputChannelCount: Int {
        parameters.channelCount
    }

    public init(parameters: AudioCodecParameters) throws {
        try WMADecoder.validate(parameters)
        session = try FFmpegCodecSession(codec: AV_CODEC_ID_WMAV2) { context in
            try WMADecoder.configure(context, parameters: parameters)
        }
        self.parameters = parameters
    }

    /// Decodes one compressed packet. The result may be empty: the decoder buffers input
    /// and only emits a frame once it has enough.
    public func decode(packet data: Data) throws -> [Float] {
        try session.send(data)
        return try drainFrames()
    }

    /// Flushes the decoder and returns the PCM it was still holding. Hand it no further
    /// packets without calling `reset()` first.
    public func flush() throws -> [Float] {
        try session.sendEnd()
        return try drainFrames()
    }

    /// Drops buffered state so the same decoder can restart at another packet.
    public func reset() {
        session.reset()
    }

    /// Decodes a whole packet sequence into one array. A music file is about 37 MB of
    /// PCM, so sweeps and playback use the streaming overload.
    public static func decode(
        packets: [Data],
        parameters: AudioCodecParameters
    ) throws -> DecodedAudio {
        var samples: [Float] = []
        try decode(packets: packets, parameters: parameters) { chunk in
            samples.append(contentsOf: chunk)
        }
        return DecodedAudio(
            sampleRate: parameters.sampleRate,
            channelCount: parameters.channelCount,
            samples: samples
        )
    }

    /// Decodes `packets` and hands each non-empty PCM chunk to `onChunk`, so memory
    /// stays flat. Output is interleaved Float at the source rate and channel count.
    public static func decode(
        packets: [Data],
        parameters: AudioCodecParameters,
        onChunk: (_ samples: [Float]) throws -> Void
    ) throws {
        let decoder = try WMADecoder(parameters: parameters)
        for packet in packets {
            let samples = try decoder.decode(packet: packet)
            if !samples.isEmpty {
                try onChunk(samples)
            }
        }
        let tail = try decoder.flush()
        if !tail.isEmpty {
            try onChunk(tail)
        }
    }

    private func drainFrames() throws -> [Float] {
        try session.receiveSamples(resampler: &resampler)
    }
}
