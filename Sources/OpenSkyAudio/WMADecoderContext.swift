// Header validation and codec context setup for WMADecoder.

import CFFmpeg
import Foundation

nonisolated extension WMADecoder {
    /// Rejects header values the decoder cannot act on before anything is allocated, so a
    /// malformed container fails cheaply and with a specific error.
    public static func validate(_ parameters: AudioCodecParameters) throws {
        guard parameters.formatTag == wmaV2FormatTag else {
            throw FFmpegDecoderError.unsupportedFormatTag(parameters.formatTag)
        }
        guard (1 ... maximumChannelCount).contains(parameters.channelCount) else {
            throw FFmpegDecoderError.invalidParameters(
                "channel count \(parameters.channelCount) outside 1...\(maximumChannelCount)"
            )
        }
        guard parameters.sampleRate > 0, parameters.sampleRate <= 384_000 else {
            throw FFmpegDecoderError.invalidParameters("sample rate \(parameters.sampleRate)")
        }
        guard parameters.blockAlign > 0 else {
            throw FFmpegDecoderError.invalidParameters("block align \(parameters.blockAlign)")
        }
        guard parameters.averageBytesPerSecond >= 0 else {
            throw FFmpegDecoderError.invalidParameters(
                "average bytes per second \(parameters.averageBytesPerSecond)"
            )
        }
    }

    /// Sets the xWMA header fields on the codec context before it opens.
    static func configure(
        _ context: UnsafeMutablePointer<AVCodecContext>,
        parameters: AudioCodecParameters
    ) throws {
        context.pointee.sample_rate = Int32(parameters.sampleRate)
        context.pointee.block_align = Int32(parameters.blockAlign)
        context.pointee.bit_rate = Int64(parameters.averageBytesPerSecond) * 8
        av_channel_layout_default(&context.pointee.ch_layout, Int32(parameters.channelCount))
        try FFmpegCodecSession.attachExtradata(parameters.extradata, to: context)
    }
}
