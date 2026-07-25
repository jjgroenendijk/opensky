// Bridges a framed xWMA container to the WMA decoder, including the extradata
// policy the container parser deliberately does not own (docs/formats/xwm.md).
//
// Vanilla Skyrim SE `.xwm` carries `cbSize == 0`, so `XWMCodecParameters.extraData`
// is empty, while ffmpeg's WMAv2 decoder reads its stream configuration flags from
// extradata. FFmpeg's own xWMA demuxer solves this by synthesizing a six-byte
// WMAv2 extradata block with byte 4 set to 31, described in its source as an
// experimentally obtained value:
//   https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/xwma.c
// OpenSky applies the same substitution here, at the decode boundary. Verified
// against the real install 2026-07-25: with the synthesized block every vanilla
// file decodes to exactly the frame count its `dpds` table declares; see
// docs/engine/audio.md.

import Foundation

extension AudioCodecParameters {
    /// The six-byte WMAv2 extradata block ffmpeg's xWMA demuxer synthesizes when
    /// the container carries none (byte 4 = 31, all others zero).
    static let synthesizedWMAv2Extradata = Data([0, 0, 0, 0, 31, 0])

    /// Decoder parameters for a framed `.xwm` file. Empty container extradata is
    /// replaced with the synthesized WMAv2 block; explicit extradata passes
    /// through untouched.
    init(xwm codec: XWMCodecParameters) {
        self.init(
            formatTag: codec.formatTag,
            channelCount: codec.channelCount,
            sampleRate: codec.sampleRate,
            blockAlign: codec.blockAlign,
            averageBytesPerSecond: codec.averageBytesPerSecond,
            extradata: codec.extraData.isEmpty
                ? Self.synthesizedWMAv2Extradata
                : codec.extraData
        )
    }
}
