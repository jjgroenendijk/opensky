// Synthetic codec parameters and packet payloads for WMADecoder tests. Nothing here comes
// from a game install: the headers are hand-written WAVEFORMATEX values and the packet
// bodies are deterministic pseudo-random bytes standing in for a corrupt stream.

import Foundation
@testable import opensky

enum WMADecoderFixture {
    /// A plausible stereo WMAv2 header of the shape an xWMA "fmt " chunk carries.
    static func parameters(
        formatTag: UInt16 = WMADecoder.wmaV2FormatTag,
        channelCount: Int = 2,
        sampleRate: Int = 44100,
        blockAlign: Int = 2972,
        averageBytesPerSecond: Int = 16000,
        extradata: Data = wmaV2Extradata
    ) -> AudioCodecParameters {
        AudioCodecParameters(
            formatTag: formatTag,
            channelCount: channelCount,
            sampleRate: sampleRate,
            blockAlign: blockAlign,
            averageBytesPerSecond: averageBytesPerSecond,
            extradata: extradata
        )
    }

    /// The ten codec-private bytes WMAv2 streams carry: a 32-bit sample count per frame,
    /// then 16-bit flags1 and flags2. Values chosen to be internally consistent rather than
    /// copied from any file.
    static let wmaV2Extradata = Data([
        0x00, 0x08, 0x00, 0x00, // samples per frame
        0x00, 0x00, // flags1 low
        0x0F, 0x00, // flags1 high
        0x00, 0x00 // flags2
    ])

    /// Deterministic noise, so a "decoder survives garbage" test is reproducible.
    static func noisePacket(byteCount: Int, seed: UInt64 = 0x5DEE_CE66) -> Data {
        var state = seed
        var bytes = [UInt8]()
        bytes.reserveCapacity(byteCount)
        for _ in 0 ..< byteCount {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            bytes.append(UInt8(truncatingIfNeeded: state >> 33))
        }
        return Data(bytes)
    }
}
