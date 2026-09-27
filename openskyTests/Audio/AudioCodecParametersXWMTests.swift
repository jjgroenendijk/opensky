// The xWMA-to-decoder bridge owns the extradata policy the container parser
// declines (docs/formats/xwm.md): empty container extradata is replaced with
// ffmpeg's synthesized six-byte WMAv2 block (byte 4 = 31), explicit extradata
// passes through untouched.

import Foundation
@testable import opensky
import Testing

struct AudioCodecParametersXWMTests {
    private func codec(extraData: Data) -> XWMCodecParameters {
        XWMCodecParameters(
            formatTag: 0x0161, channelCount: 2, sampleRate: 44100,
            averageBytesPerSecond: 24000, blockAlign: 2230, bitsPerSample: 16,
            extraData: extraData
        )
    }

    @Test
    func emptyExtradataIsSynthesized() {
        let parameters = AudioCodecParameters(xwm: codec(extraData: Data()))
        #expect(parameters.extradata == Data([0, 0, 0, 0, 31, 0]))
        #expect(parameters.formatTag == 0x0161)
        #expect(parameters.channelCount == 2)
        #expect(parameters.sampleRate == 44100)
        #expect(parameters.blockAlign == 2230)
        #expect(parameters.averageBytesPerSecond == 24000)
    }

    @Test
    func explicitExtradataPassesThrough() {
        let explicit = Data([1, 2, 3, 4, 5, 6])
        let parameters = AudioCodecParameters(xwm: codec(extraData: explicit))
        #expect(parameters.extradata == explicit)
    }
}
