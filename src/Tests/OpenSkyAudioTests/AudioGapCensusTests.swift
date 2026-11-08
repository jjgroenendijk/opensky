// AudioGapCensus: sound file variants the engine opens, and the ones it does not.

import Foundation
@testable import OpenSkyAudio
import OpenSkyFormatsCore
import OpenSkyFormatsTesting
import Testing

struct AudioGapCensusTests {
    @Test func sortsSoundFilesIntoReadAndFailingVariants() {
        var census = AudioGapCensus()
        census.record(
            path: "sound\\fx\\a.wav",
            data: WAVFixture.file(channels: 1, sampleRate: 22050, bits: 16, samples: [0, 1])
        )
        census.record(path: "sound\\fx\\b.xwm", data: Data("not a sound".utf8))

        #expect(census.variants.uses["wav wav format 0x1 16-bit"] == 1)
        #expect(census.variants.done(where: AudioGapCensus.isRead) == 1)
        #expect(census.variants.left(where: AudioGapCensus.isRead).first?.name
            .hasPrefix("fails: xwm: ") == true)
    }
}
