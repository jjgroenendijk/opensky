// Codec description handed to WMADecoder by whichever container framed the payload.
// The fields mirror WAVEFORMATEX, which is what an xWMA RIFF "fmt " chunk carries, but the
// type is deliberately container-agnostic so a future container can reuse the decoder.
// See docs/decisions/ffmpeg-audio.md.

import Foundation

/// Everything the decoder needs to interpret a stream of compressed packets.
nonisolated struct AudioCodecParameters: Equatable, Sendable {
    /// `WAVEFORMATEX.wFormatTag`. WMAv2 is `0x0161`.
    let formatTag: UInt16
    let channelCount: Int
    let sampleRate: Int
    /// `WAVEFORMATEX.nBlockAlign`: the size in bytes of one compressed packet.
    let blockAlign: Int
    /// `WAVEFORMATEX.nAvgBytesPerSec`, used only to reconstruct the nominal bit rate.
    let averageBytesPerSecond: Int
    /// `WAVEFORMATEX.cbSize` bytes of codec-private data following the fixed header.
    let extradata: Data
}

/// Decoded PCM: interleaved 32-bit float, native endianness, one canonical shape whatever
/// sample format the underlying decoder happened to produce.
nonisolated struct DecodedAudio: Equatable, Sendable {
    let sampleRate: Int
    let channelCount: Int
    let samples: [Float]

    /// Sample frames, that is one value per channel counted once.
    var frameCount: Int {
        channelCount > 0 ? samples.count / channelCount : 0
    }

    var duration: Double {
        sampleRate > 0 ? Double(frameCount) / Double(sampleRate) : 0
    }
}

/// Failures the decoder reports. Every case is recoverable by the caller: nothing here
/// leaves a half-built decoder behind, and no case is reachable from valid input.
nonisolated enum WMADecoderError: Error, Equatable {
    /// The container described a codec this decoder does not implement.
    case unsupportedFormatTag(UInt16)
    /// A header field is outside the range the decoder can act on.
    case invalidParameters(String)
    /// The linked ffmpeg build has no WMAv2 decoder, which means it was misconfigured.
    case decoderUnavailable
    /// An ffmpeg allocation returned null; the argument names what could not be allocated.
    case allocationFailed(String)
    /// `avcodec_open2` refused the parameters; the code is the raw ffmpeg error.
    case openFailed(code: Int32)
    /// A packet could not be decoded; the code is the raw ffmpeg error.
    case decodeFailed(code: Int32)
    /// Conversion to interleaved float failed; the code is the raw ffmpeg error.
    case resampleFailed(code: Int32)
    /// The decoder emitted a sample format libswresample declined to convert.
    case unsupportedSampleFormat(Int32)
}
