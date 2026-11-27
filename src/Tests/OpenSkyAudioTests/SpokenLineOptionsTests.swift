// How an INFO's response flags voice its line (docs/engine/dialogue.md, response flags).

@testable import OpenSkyAudio
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import Testing

struct SpokenLineOptionsTests {
    /// ENAM 0x800 drops the lip track; ENAM 0x2000 routes the line through ONAM.
    @Test func theResponseFlagsSetLipSyncAndTheOutputModel() throws {
        let override = try DialogueFixture.info(
            DialogueFixture.infoData(flags: 0x2800) + DialogueFixture.word("ONAM", 0x801)
        )
        #expect(SpokenLineOptions(override) == SpokenLineOptions(
            lipSync: false, outputModel: FormID(0x801)
        ))
        let unflagged = try DialogueFixture.info(DialogueFixture.word("ONAM", 0x801))
        #expect(SpokenLineOptions(unflagged) == .standard)
    }
}
