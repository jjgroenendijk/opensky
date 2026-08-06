// libswresample wrapper that normalizes whatever an ffmpeg decoder emits into interleaved
// 32-bit float at the source sample rate. Owning this in its own class keeps the SwrContext
// lifetime a single, obvious pair: allocated in init, released in deinit, never elsewhere.
// See docs/decisions/ffmpeg-audio.md.

import CFFmpeg
import Foundation

nonisolated final class FFmpegResampler {
    /// `SwrContext` is opaque in the public headers, so Swift imports it as `OpaquePointer`.
    private var context: OpaquePointer?
    let channelCount: Int
    let sampleRate: Int

    /// Builds a converter matched to the first decoded frame: same channel layout, same
    /// sample rate, sample format forced to `AV_SAMPLE_FMT_FLT`.
    init(matching frame: UnsafeMutablePointer<AVFrame>) throws {
        let sourceFormat = frame.pointee.format
        guard sourceFormat >= 0 else {
            throw WMADecoderError.unsupportedSampleFormat(sourceFormat)
        }
        channelCount = Int(frame.pointee.ch_layout.nb_channels)
        sampleRate = Int(frame.pointee.sample_rate)

        // The output layout is a copy, because a custom layout owns heap storage that must
        // be released whether swr_alloc_set_opts2 succeeds or not.
        var outputLayout = AVChannelLayout()
        let copyStatus = av_channel_layout_copy(&outputLayout, &frame.pointee.ch_layout)
        guard copyStatus >= 0 else { throw WMADecoderError.resampleFailed(code: copyStatus) }
        defer { av_channel_layout_uninit(&outputLayout) }

        var created: OpaquePointer?
        let status = swr_alloc_set_opts2(
            &created,
            &outputLayout, AV_SAMPLE_FMT_FLT, frame.pointee.sample_rate,
            &frame.pointee.ch_layout, AVSampleFormat(rawValue: sourceFormat),
            frame.pointee.sample_rate,
            0, nil
        )
        guard status >= 0 else {
            swr_free(&created)
            throw WMADecoderError.resampleFailed(code: status)
        }
        guard created != nil else { throw WMADecoderError.allocationFailed("SwrContext") }

        let initStatus = swr_init(created)
        guard initStatus >= 0 else {
            swr_free(&created)
            throw WMADecoderError.resampleFailed(code: initStatus)
        }
        context = created
    }

    deinit { swr_free(&context) }

    /// Converts one decoded frame. The returned array is interleaved and sized to the
    /// samples libswresample actually wrote, which can differ from the frame's own count.
    func interleavedFloats(from frame: UnsafeMutablePointer<AVFrame>) throws -> [Float] {
        guard let context else { throw WMADecoderError.allocationFailed("SwrContext") }
        guard let extended = frame.pointee.extended_data else { return [] }
        let inputCount = frame.pointee.nb_samples
        let capacity = Int(swr_get_out_samples(context, inputCount))
        guard capacity > 0, channelCount > 0 else { return [] }

        var output = [Float](repeating: 0, count: capacity * channelCount)
        let written = output.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return 0 }
            var plane: UnsafeMutablePointer<UInt8>? = UnsafeMutableRawPointer(base)
                .assumingMemoryBound(to: UInt8.self)
            let input = UnsafeRawPointer(extended)
                .assumingMemoryBound(to: UnsafePointer<UInt8>?.self)
            return swr_convert(context, &plane, Int32(capacity), input, inputCount)
        }
        guard written >= 0 else { throw WMADecoderError.resampleFailed(code: written) }
        output.removeLast(output.count - Int(written) * channelCount)
        return output
    }
}
