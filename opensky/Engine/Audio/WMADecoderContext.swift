// Header validation and AVCodecContext construction for WMADecoder. Split out of
// WMADecoder.swift so the decode loop and the one-time C setup stay separately readable.
//
// `makeContext` owns everything it allocates until its final statement: the deferred
// cleanup runs on every throw and only stands down once the caller is about to receive the
// pointer, which the caller records in FFmpegDecodeResources with no throw in between.

import CFFmpeg
import Foundation

nonisolated extension WMADecoder {
    /// Rejects header values the decoder cannot act on before anything is allocated, so a
    /// malformed container fails cheaply and with a specific error.
    static func validate(_ parameters: AudioCodecParameters) throws {
        guard parameters.formatTag == wmaV2FormatTag else {
            throw WMADecoderError.unsupportedFormatTag(parameters.formatTag)
        }
        guard (1 ... maximumChannelCount).contains(parameters.channelCount) else {
            throw WMADecoderError.invalidParameters(
                "channel count \(parameters.channelCount) outside 1...\(maximumChannelCount)"
            )
        }
        guard parameters.sampleRate > 0, parameters.sampleRate <= 384_000 else {
            throw WMADecoderError.invalidParameters("sample rate \(parameters.sampleRate)")
        }
        guard parameters.blockAlign > 0 else {
            throw WMADecoderError.invalidParameters("block align \(parameters.blockAlign)")
        }
        guard parameters.averageBytesPerSecond >= 0 else {
            throw WMADecoderError.invalidParameters(
                "average bytes per second \(parameters.averageBytesPerSecond)"
            )
        }
    }

    /// Allocates, configures and opens the codec context. Frees it again on every failure.
    static func makeContext(
        _ parameters: AudioCodecParameters
    ) throws -> UnsafeMutablePointer<AVCodecContext> {
        guard let codec = avcodec_find_decoder(AV_CODEC_ID_WMAV2) else {
            throw WMADecoderError.decoderUnavailable
        }
        guard let context = avcodec_alloc_context3(codec) else {
            throw WMADecoderError.allocationFailed("AVCodecContext")
        }
        var owning: UnsafeMutablePointer<AVCodecContext>? = context
        var handedOver = false
        defer {
            if !handedOver {
                avcodec_free_context(&owning)
            }
        }

        context.pointee.sample_rate = Int32(parameters.sampleRate)
        context.pointee.block_align = Int32(parameters.blockAlign)
        context.pointee.bit_rate = Int64(parameters.averageBytesPerSecond) * 8
        av_channel_layout_default(&context.pointee.ch_layout, Int32(parameters.channelCount))
        try attachExtradata(parameters.extradata, to: context)

        let status = avcodec_open2(context, codec, nil)
        guard status >= 0 else { throw WMADecoderError.openFailed(code: status) }
        handedOver = true
        return context
    }

    /// Copies codec-private bytes into an ffmpeg-owned buffer. libavcodec requires
    /// `AV_INPUT_BUFFER_PADDING_SIZE` readable zero bytes past the end, and takes ownership:
    /// `avcodec_free_context` releases this allocation.
    private static func attachExtradata(
        _ extradata: Data,
        to context: UnsafeMutablePointer<AVCodecContext>
    ) throws {
        guard !extradata.isEmpty else { return }
        let size = extradata.count
        guard let buffer = av_mallocz(size + Int(AV_INPUT_BUFFER_PADDING_SIZE)) else {
            throw WMADecoderError.allocationFailed("extradata")
        }
        extradata.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                memcpy(buffer, base, size)
            }
        }
        context.pointee.extradata = buffer.assumingMemoryBound(to: UInt8.self)
        context.pointee.extradata_size = Int32(size)
    }
}
