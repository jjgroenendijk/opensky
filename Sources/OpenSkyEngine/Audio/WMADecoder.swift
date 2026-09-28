// WMAv2 packet decoder: compressed packets in, interleaved 32-bit float PCM out.
//
// This is OpenSky's only C-interop boundary onto ffmpeg. No AVCodecContext, AVPacket or
// AVFrame pointer escapes this file; callers see Data in and [Float] out.
//
// Lifetime discipline: every ffmpeg object lives in FFmpegDecodeResources, whose deinit is
// the single place anything is freed. The initializer builds that holder as a local, so a
// throw at any point releases it and frees whatever had been allocated so far — which
// matters because Swift does not run a class deinit when its initializer throws.
//
// Codec parameters come from the container, not from a bitstream probe, because xWMA
// carries a WAVEFORMATEX header and no in-band codec configuration.
// See docs/decisions/ffmpeg-audio.md.

import CFFmpeg
import Foundation

/// Sole owner of the ffmpeg allocations backing one decoder.
nonisolated private final class FFmpegDecodeResources {
    var context: UnsafeMutablePointer<AVCodecContext>?
    var packet: UnsafeMutablePointer<AVPacket>?
    var frame: UnsafeMutablePointer<AVFrame>?

    deinit {
        // avcodec_free_context also frees the extradata buffer handed to the context.
        avcodec_free_context(&context)
        av_packet_free(&packet)
        av_frame_free(&frame)
    }
}

nonisolated final class WMADecoder {
    /// `WAVEFORMATEX.wFormatTag` for Windows Media Audio 2, the codec xWMA carries.
    static let wmaV2FormatTag: UInt16 = 0x0161
    /// Above this the decoder rejects the header rather than trusting a wild channel count.
    static let maximumChannelCount = 8

    /// ffmpeg reports "send me more input" and "fully drained" as negative status values.
    private enum Status {
        static let again = -Int32(EAGAIN)
        /// `AVERROR_EOF`: the negated packed tag `'E','O','F',' '`.
        static let endOfFile = -0x2046_4F45
    }

    let parameters: AudioCodecParameters

    private let resources: FFmpegDecodeResources
    private let context: UnsafeMutablePointer<AVCodecContext>
    private let packet: UnsafeMutablePointer<AVPacket>
    private let frame: UnsafeMutablePointer<AVFrame>
    private var resampler: FFmpegResampler?

    /// Sample rate of the PCM this decoder produces, equal to the container's rate.
    var outputSampleRate: Int {
        parameters.sampleRate
    }

    /// Channel count of the PCM this decoder produces, equal to the container's count.
    var outputChannelCount: Int {
        parameters.channelCount
    }

    init(parameters: AudioCodecParameters) throws {
        try WMADecoder.validate(parameters)
        let owned = FFmpegDecodeResources()
        let context = try WMADecoder.makeContext(parameters)
        owned.context = context
        guard let packet = av_packet_alloc() else {
            throw WMADecoderError.allocationFailed("AVPacket")
        }
        owned.packet = packet
        guard let frame = av_frame_alloc() else {
            throw WMADecoderError.allocationFailed("AVFrame")
        }
        owned.frame = frame

        self.parameters = parameters
        resources = owned
        self.context = context
        self.packet = packet
        self.frame = frame
    }

    /// Decodes one compressed packet. The result may be empty: the decoder buffers input
    /// and only emits a frame once it has enough.
    func decode(packet data: Data) throws -> [Float] {
        try send(data)
        return try drainFrames()
    }

    /// Flushes the decoder and returns the PCM it was still holding. Hand it no further
    /// packets without calling `reset()` first.
    func flush() throws -> [Float] {
        let status = avcodec_send_packet(context, nil)
        guard status >= 0 || status == Status.endOfFile else {
            throw WMADecoderError.decodeFailed(code: status)
        }
        return try drainFrames()
    }

    /// Drops buffered state so the same decoder can restart at another packet.
    func reset() {
        avcodec_flush_buffers(context)
    }

    /// Decodes a whole packet sequence, the shape a file-at-a-time caller wants.
    /// Hands the full PCM back in one array, which is fine for short clips and the
    /// one-file inspection paths but materializes the whole track: a vanilla music
    /// file decodes to roughly 37 MB. Whole-corpus sweeps and playback should use the
    /// streaming overload below instead (issue #218).
    static func decode(packets: [Data], parameters: AudioCodecParameters) throws -> DecodedAudio {
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

    /// Decodes `packets` and hands each non-empty PCM chunk to `onChunk` instead of
    /// accumulating the whole file. The decoder buffers input, so a packet often
    /// yields no PCM until enough have arrived; those empty results are not passed
    /// to `onChunk`. The final flush is delivered the same way when it produces PCM.
    ///
    /// Use this over the accumulating overload whenever the caller does not need the
    /// full PCM at once: a streaming consumer discards each chunk as it goes and
    /// stays flat in memory across a whole-corpus sweep or a long playback session
    /// (issue #218). The callback receives interleaved float at the source sample
    /// rate and channel count, matching the accumulating overload's output.
    static func decode(
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

    // MARK: - Packet submission

    private func send(_ data: Data) throws {
        guard !data.isEmpty else { return }
        // libavcodec copies the payload into its own padded, reference-counted buffer, so
        // the borrowed pointer only has to stay valid across avcodec_send_packet.
        let status = data.withUnsafeBytes { raw -> Int32 in
            guard let base = raw.baseAddress else { return 0 }
            packet.pointee.data = UnsafeMutableRawPointer(mutating: base)
                .assumingMemoryBound(to: UInt8.self)
            packet.pointee.size = Int32(raw.count)
            defer {
                packet.pointee.data = nil
                packet.pointee.size = 0
            }
            return avcodec_send_packet(context, packet)
        }
        guard status >= 0 else { throw WMADecoderError.decodeFailed(code: status) }
    }

    private func drainFrames() throws -> [Float] {
        var samples: [Float] = []
        while true {
            let status = avcodec_receive_frame(context, frame)
            if status == Status.again || status == Status.endOfFile {
                break
            }
            guard status >= 0 else { throw WMADecoderError.decodeFailed(code: status) }
            // The frame's buffers are recycled on the next receive, so unref on every path.
            defer { av_frame_unref(frame) }
            try samples.append(contentsOf: convert(frame))
        }
        return samples
    }

    private func convert(_ frame: UnsafeMutablePointer<AVFrame>) throws -> [Float] {
        let converter: FFmpegResampler
        if let resampler {
            converter = resampler
        } else {
            converter = try FFmpegResampler(matching: frame)
            resampler = converter
        }
        return try converter.interleavedFloats(from: frame)
    }
}
