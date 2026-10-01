// Bridges a framed xWMA container to the WMA decoder. Vanilla `.xwm` has
// `cbSize == 0`, but ffmpeg's WMAv2 decoder reads flags from extradata, so this
// synthesizes the six-byte block with byte 4 = 31, as ffmpeg's xwma.c demuxer does.
// With it every vanilla file decodes to its `dpds` frame count.
// See docs/formats/xwm.md and docs/engine/audio-decoding.md.

import Foundation
import OpenSkyFormatsAudio

nonisolated extension AudioCodecParameters {
    /// The six-byte WMAv2 extradata block ffmpeg's xWMA demuxer synthesizes when
    /// the container carries none (byte 4 = 31, all others zero).
    public static let synthesizedWMAv2Extradata = Data([0, 0, 0, 0, 31, 0])

    /// Decoder parameters for a framed `.xwm` file. Empty container extradata is
    /// replaced with the synthesized WMAv2 block; explicit extradata passes
    /// through untouched.
    public init(xwm codec: XWMCodecParameters) {
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
